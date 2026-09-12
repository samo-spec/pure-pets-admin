//
//  PPAccessoryEditorView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Category-defining Biological Registry & Inventory Command Center.
//  Preserves 100% backend contract parity with PetAccessory, AccessoryManager,
//  PPLivePetInventoryService, Firebase Storage, and AppManager.
//

import SwiftUI
import PhotosUI
import AVFoundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions

// MARK: - Sendable Conformance

extension MainKindsModel: @unchecked Sendable {}
extension SubKindModel: @unchecked Sendable {}

// MARK: - Navigation Stages & Digital Twin Modes

enum PPEditorStage: Int, CaseIterable, Identifiable {
    case identity = 0
    case bioVault = 1
    case pricing = 2
    case governance = 3

    var id: Int { rawValue }

    func localizedTitle(isLivePet: Bool) -> String {
        switch self {
        case .identity:
            return Language.get("Stage_Identity", alter: "الهوية والوسائط")
        case .bioVault:
            return isLivePet
                ? Language.get("Stage_BioVault", alter: "السجل الحيوي والطبي")
                : Language.get("Stage_Specs", alter: "المواصفات والنوع")
        case .pricing:
            return Language.get("Stage_Pricing", alter: "التسعير والأرباح")
        case .governance:
            return Language.get("Stage_Governance", alter: "التوزيع والاعتماد")
        }
    }

    var symbol: String {
        switch self {
        case .identity: return "sparkles.rectangle.stack.fill"
        case .bioVault: return "heart.text.square.fill"
        case .pricing: return "chart.line.uptrend.xyaxis.circle.fill"
        case .governance: return "shield.checkered"
        }
    }
}

enum PPDigitalTwinMode: String, CaseIterable, Identifiable {
    case marketplace
    case posTerminal

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .marketplace:
            return Language.get("Twin_Marketplace", alter: "المتجر للعملاء 📱")
        case .posTerminal:
            return Language.get("Twin_POS", alter: "شاشة الكاشير والـ POS 📟")
        }
    }
}

enum PPLivePetSubmissionFailureKind {
    case denied
    case conflict
    case invalid
    case stale
    case ambiguous
    case retryable

    var preservesExactRecovery: Bool {
        switch self {
        case .ambiguous, .retryable:
            return true
        case .denied, .conflict, .invalid, .stale:
            return false
        }
    }
}

private struct PPLivePetMutationRecovery: Codable {
    let action: String
    let productID: String?
    let commandID: String?
    let payloadData: Data
    let catalogValuesData: Data
    let catalogCommandID: String?
    var acceptedProductID: String?
    var acceptedRevision: Int?
    var successMessage: String
    let oldImageURLs: [String]
}

/// Prepared, command-bound media for exactly one draft animal.
///
/// Bytes are normalized before hashing so retries keep one immutable Storage
/// object path. The remote URL is retained only after Storage confirms it; it is
/// then serialized into the existing live-unit `mediaURLs` contract.
struct PPLivePetUnitPhotoDraft {
    let image: UIImage
    let encodedData: Data
    let contentSHA256: String
    var objectWasUploaded: Bool
    var uploadedURL: String?
}

struct PPLivePetUnitPhotoMetadataSnapshot: Sendable {
    let contentType: String?
    let size: Int64
    let customMetadata: [String: String]
}

struct PPLivePetUnitPhotoStorageService {
    static func prepareLivePetUnitPhoto(_ source: UIImage) -> PPLivePetUnitPhotoDraft? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }

        let longestEdge = max(source.size.width, source.size.height)
        let scale = min(1, 1_800 / longestEdge)
        let targetSize = CGSize(
            width: max(1, (source.size.width * scale).rounded()),
            height: max(1, (source.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let maximumBytes = 10 * 1_024 * 1_024
        let encoded = [0.82, 0.72, 0.62, 0.52]
            .compactMap { normalized.jpegData(compressionQuality: $0) }
            .first { !$0.isEmpty && $0.count < maximumBytes }
        guard let encoded else { return nil }

        let digest = SHA256.hash(data: encoded)
            .map { String(format: "%02x", $0) }
            .joined()
        return PPLivePetUnitPhotoDraft(
            image: normalized,
            encodedData: encoded,
            contentSHA256: digest,
            objectWasUploaded: false,
            uploadedURL: nil
        )
    }

    static func upload(
        photo: inout PPLivePetUnitPhotoDraft,
        unitID: String,
        commandID: String,
        actorUID: String
    ) async throws -> String {
        if let uploadedURL = photo.uploadedURL, !uploadedURL.isEmpty {
            return uploadedURL
        }

        let objectName = "\(photo.contentSHA256)_identity.jpg"
        let reference = Storage.storage().reference()
            .child("live-pet-units")
            .child(actorUID)
            .child(commandID)
            .child(unitID)
            .child(objectName)
        let expectedMetadata: [String: String] = [
            "uploaded_by": actorUID,
            "media_type": "image",
            "media_scope": "live_pet_unit_internal",
            "command_id": commandID,
            "draft_unit_id": unitID,
            "content_sha256": photo.contentSHA256,
        ]

        if let existingMetadata = try await livePetUnitPhotoMetadata(for: reference) {
            guard existingMetadata.contentType == "image/jpeg",
                  existingMetadata.size == Int64(photo.encodedData.count),
                  expectedMetadata.allSatisfy({ existingMetadata.customMetadata[$0.key] == $0.value }) else {
                throw livePetUnitPhotoError(
                    code: 3,
                    key: "LivePetIntake_UnitPhotoStagedConflict",
                    fallback: "تعارضت الصورة المجهزة مع ملف موجود. اختر الصورة مجدداً وحاول مرة أخرى."
                )
            }
            photo.objectWasUploaded = true
        } else {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            metadata.customMetadata = expectedMetadata
            try await putLivePetUnitPhoto(photo.encodedData, metadata: metadata, at: reference)
            photo.objectWasUploaded = true
        }

        let downloadURL = try await livePetUnitPhotoDownloadURL(for: reference)
        photo.uploadedURL = downloadURL.absoluteString
        return downloadURL.absoluteString
    }

    static func livePetUnitPhotoMetadata(
        for reference: StorageReference
    ) async throws -> PPLivePetUnitPhotoMetadataSnapshot? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                reference.getMetadata { metadata, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let metadata {
                        continuation.resume(returning: PPLivePetUnitPhotoMetadataSnapshot(
                            contentType: metadata.contentType,
                            size: metadata.size,
                            customMetadata: metadata.customMetadata ?? [:]
                        ))
                    } else {
                        continuation.resume(throwing: self.livePetUnitPhotoError(
                            code: 4,
                            key: "LivePetIntake_UnitPhotoUploadFailed",
                            fallback: "تعذر التحقق من صورة الحيوان المرفوعة. حاول مرة أخرى."
                        ))
                    }
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain,
               nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return nil
            }
            throw error
        }
    }

    static func putLivePetUnitPhoto(
        _ data: Data,
        metadata: StorageMetadata,
        at reference: StorageReference
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func livePetUnitPhotoDownloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: self.livePetUnitPhotoError(
                        code: 5,
                        key: "LivePetIntake_UnitPhotoUploadFailed",
                        fallback: "تعذر إكمال رفع صورة الحيوان. حاول مرة أخرى."
                    ))
                }
            }
        }
    }

    static func livePetUnitPhotoError(code: Int, key: String, fallback: String) -> NSError {
        NSError(
            domain: "PPAdmin.LivePetUnitPhoto",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: Language.get(key, alter: fallback)]
        )
    }
}


// MARK: - Unified Quantity Group Draft

struct PPQuantityGroupDraft: Identifiable, Equatable, Sendable {
    var id: String
    var nameAr: String
    var nameEn: String
    var unitsPerGroup: Int
    var barcode: String
    var sku: String
    var sortOrder: Int
    var retailEnabled: Bool
    var wholesaleEnabled: Bool
    var retailPriceText: String
    var wholesalePriceText: String
    var defaultForRetail: Bool
    var defaultForWholesale: Bool
    var active: Bool

    var retailPrice: Double {
        Double(retailPriceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    var wholesalePrice: Double {
        Double(wholesalePriceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    var retailPriceMinor: Int {
        Int((retailPrice * 100).rounded())
    }
    var wholesalePriceMinor: Int? {
        wholesaleEnabled ? Int((wholesalePrice * 100).rounded()) : nil
    }

    var localizedName: String {
        Language.isRTL()
            ? (nameAr.isEmpty ? nameEn : nameAr)
            : (nameEn.isEmpty ? nameAr : nameEn)
    }

    var unitsCountText: String {
        if unitsPerGroup == 1 {
            return Language.get("Unit_Single_Piece", alter: "1 قطعة").normalizedEnglishDigits
        }
        return String(format: Language.get("Unit_Multiple_Pieces_Format", alter: "%@ قطع"), unitsPerGroup.englishDigits).normalizedEnglishDigits
    }
}

// MARK: - Category-Defining Physical Specification Archetypes

enum PPPhysicalSpecMode: String, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case dimensions = "dimensions"      // Cages, enclosures, carriers, beds (W × H)
    case standardSize = "standardSize"  // Wearable apparel, collars, harnesses (XXS–3XL, Free Size)
    case weightVolume = "weightVolume"  // Litter, shampoos, bulk food, liquids (kg, g, L, ml)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return Language.get("PhysicalSpec_None_Title", alter: "بدون مواصفة")
        case .dimensions:
            return Language.get("PhysicalSpec_Dimensions_Title", alter: "الأبعاد (العرض × الارتفاع)")
        case .standardSize:
            return Language.get("PhysicalSpec_ApparelSize_Title", alter: "المقاس المعياري")
        case .weightVolume:
            return Language.get("PhysicalSpec_Weight_Title", alter: "الوزن أو السعة")
        }
    }

    var shortTitle: String {
        switch self {
        case .none:
            return Language.get("PhysicalSpec_None_Title", alter: "بدون")
        case .dimensions:
            return Language.get("Dimensions_Short", alter: "الأبعاد W×H")
        case .standardSize:
            return Language.get("CatalogIntake_SizeLabel", alter: "المقاس")
        case .weightVolume:
            return Language.get("CatalogIntake_WeightLabel", alter: "الوزن/السعة")
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return Language.get("PhysicalSpec_None_Subtitle", alter: "منتج بدون أبعاد أو أحجام محددة")
        case .dimensions:
            return Language.get("PhysicalSpec_Dimensions_Subtitle", alter: "للأقفاص، النواقل، والبيوت")
        case .standardSize:
            return Language.get("PhysicalSpec_ApparelSize_Subtitle", alter: "للملابس، الياقات، والأحزمة")
        case .weightVolume:
            return Language.get("PhysicalSpec_Weight_Subtitle", alter: "للرمل، الشامبو، والمستحضرات")
        }
    }

    var symbol: String {
        switch self {
        case .none:
            return "slash.circle"
        case .dimensions:
            return "square.resize"
        case .standardSize:
            return "tshirt.fill"
        case .weightVolume:
            return "scalemass.fill"
        }
    }
}

// MARK: - View Model

@MainActor
final class PPAccessoryEditorViewModel: ObservableObject {
    // MARK: - Public Inputs & Identity
    let editingAccessory: PetAccessory?
    let showTypeRow: Bool
    let onDismiss: () -> Void

    // MARK: - First-Principles Navigation & Twin State
    @Published var activeStage: PPEditorStage = .identity
    @Published var digitalTwinMode: PPDigitalTwinMode = .marketplace

    // MARK: - Form State
    @Published var selectedKind: AccessKindType {
        didSet {
            if selectedKind == .typeFood {
                condition = .new
            } else {
                hasExpiryDate = false
            }
            updateUnsavedChanges()
        }
    }
    @Published var name: String = "" { didSet { updateUnsavedChanges() } }
    @Published var nameEn: String = "" { didSet { updateUnsavedChanges() } }
    var nameAr: String {
        get { name }
        set { name = newValue }
    }
    @Published var desc: String = "" { didSet { updateUnsavedChanges() } }
    @Published var descEn: String = "" { didSet { updateUnsavedChanges() } }
    
    // Species & Breed
    @Published var selectedMainKind: MainKindsModel? = nil {
        didSet {
            if oldValue?.id != selectedMainKind?.id {
                selectedSubKind = nil
                dynamicSubKinds = []
                if let newMain = selectedMainKind {
                    fetchFreshSubKinds(for: newMain)
                }
            }
            updateUnsavedChanges()
        }
    }
    @Published var selectedSubKind: SubKindModel? = nil {
        didSet {
            if oldValue?.id != selectedSubKind?.id {
                fetchSubSubTaxonomy(for: selectedSubKind)
            }
            updateUnsavedChanges()
        }
    }
    @Published var dynamicSubKinds: [SubKindModel] = []
    @Published var dynamicSubKindsByMainKind: [Int: [SubKindModel]] = [:]
    @Published var availableSubSubKinds: [AdminSubSubKindItem] = []
    @Published var subSubKindItemsBySubSubID: [Int: [AdminSubKindItemDetail]] = [:]
    @Published var isLoadingSubSubTaxonomy: Bool = false

    var hasSubSubKinds: Bool {
        (selectedSubKind?.have_subSub == 1) || !availableSubSubKinds.isEmpty
    }

    // Multi-category & Multi-subcategory Support (Accessories & Food)
    @Published var selectedMainKinds: Set<Int> = [] {
        didSet {
            if isAllCategoriesSelected || selectedMainKinds.isEmpty {
                selectedMainKind = nil
            } else if let firstID = selectedMainKinds.first, let match = availableMainKinds.first(where: { $0.id == firstID }) {
                selectedMainKind = match
            }
            if oldValue != selectedMainKinds {
                selectedSubKinds = []
                selectedSubKind = nil
                isAllSubCategoriesSelected = false
                fetchFreshSubKindsForSelectedCategories()
            }
            updateUnsavedChanges()
        }
    }
    @Published var isAllCategoriesSelected: Bool = false {
        didSet {
            if isAllCategoriesSelected {
                selectedMainKinds = []
                selectedMainKind = nil
                fetchFreshSubKindsForSelectedCategories()
            }
            updateUnsavedChanges()
        }
    }
    @Published var selectedSubKinds: Set<Int> = [] {
        didSet {
            if isAllSubCategoriesSelected {
                selectedSubKind = nil
            } else if let firstID = selectedSubKinds.first, let match = availableSubKinds.first(where: { $0.id == firstID }) {
                selectedSubKind = match
            }
            updateUnsavedChanges()
        }
    }
    @Published var isAllSubCategoriesSelected: Bool = false {
        didSet {
            if isAllSubCategoriesSelected {
                selectedSubKinds = []
                selectedSubKind = nil
            }
            updateUnsavedChanges()
        }
    }
    
    // Live Pet Specific Lifecycle & Bio-Security Fields
    @Published var ringTag: String = "" { didSet { updateUnsavedChanges() } }
    @Published var selectedGender: String = "male" { didSet { updateUnsavedChanges() } } // male, female, pair, unspecified
    @Published var birthDate: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date() { didSet { updateUnsavedChanges() } }
    @Published var hasBirthDate: Bool = false { didSet { updateUnsavedChanges() } }
    @Published var isVaccinated: Bool = true { didSet { updateUnsavedChanges() } }
    @Published var vaccinationPassportId: String = "" { didSet { updateUnsavedChanges() } }
    @Published var isDewormed: Bool = true { didSet { updateUnsavedChanges() } }
    @Published var isMicrochipped: Bool = false { didSet { updateUnsavedChanges() } }
    @Published var livePetUnitStatus: String = "AVAILABLE" { didSet { updateUnsavedChanges() } } // AVAILABLE, RESERVED, QUARANTINED, SOLD
    @Published var reservationCustomerName: String = "" { didSet { updateUnsavedChanges() } }
    @Published var reservationCustomerPhone: String = "" { didSet { updateUnsavedChanges() } }
    @Published var liveInventoryMode: PPLivePetInventoryMode = .individual { didSet { updateUnsavedChanges() } }
    @Published var livePetUnits: [PPLivePetUnitDraft] = [PPLivePetUnitDraft()] { didSet { updateUnsavedChanges() } }
    @Published var liveSupplier: String = "" { didSet { updateUnsavedChanges() } }
    @Published var liveGroupCostText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var liveArrivalDate: Date = Date() { didSet { updateUnsavedChanges() } }
    @Published var liveIntakeNotes: String = "" { didSet { updateUnsavedChanges() } }

    // Pricing & Unified Commerce
    @Published var priceText: String = "" {
        didSet {
            updateUnsavedChanges()
            syncBasePriceToSingleGroup()
        }
    }
    @Published var wholesaleEnabled: Bool = false {
        didSet {
            updateUnsavedChanges()
            syncWholesaleStateToSingleGroup()
        }
    }
    @Published var wholesalePriceText: String = "" {
        didSet {
            updateUnsavedChanges()
            syncWholesalePriceToGroups()
        }
    }
    @Published var discountPercentText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var discountAmountText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var costPriceText: String = "" { didSet { updateUnsavedChanges() } }

    // Unified Quantity Groups
    @Published var commerceBaseUnitID: String = "piece" { didSet { updateUnsavedChanges() } }
    @Published var commerceBaseUnitNameAr: String = "قطعة" { didSet { updateUnsavedChanges() } }
    @Published var commerceBaseUnitNameEn: String = "Piece" { didSet { updateUnsavedChanges() } }
    @Published var quantityGroups: [PPQuantityGroupDraft] = [] { didSet { updateUnsavedChanges() } }
    @Published var pricingRevision: Int = 1
    @Published var showQuantityGroupInspector: Bool = false
    @Published var selectedQuantityGroupForEditing: PPQuantityGroupDraft? = nil
    @Published var isLoadingCommerce: Bool = false
    
    // Inventory, SKU & Stock
    @Published var sku: String = "" { didSet { updateUnsavedChanges() } }
    @Published var barcode: String = "" { didSet { updateUnsavedChanges() } }
    @Published var quantity: Int = 1 { didSet { updateUnsavedChanges() } }
    @Published var condition: AccessConditions = .new { didSet { updateUnsavedChanges() } }

    // Category-Defining Physical Specification Engine
    @Published var physicalSpecMode: PPPhysicalSpecMode = .none { didSet { updateUnsavedChanges() } }
    @Published var dimensionWidthText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var dimensionHeightText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var dimensionUnit: String = "cm" { didSet { updateUnsavedChanges() } }
    @Published var size: String = "" { didSet { updateUnsavedChanges() } }
    @Published var weightText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var weightUnit: String = "kg" { didSet { updateUnsavedChanges() } }
    
    // Expiry Date
    @Published var hasExpiryDate: Bool = false { didSet { updateUnsavedChanges() } }
    @Published var expiryDate: Date = Date().addingTimeInterval(86400 * 180) { didSet { updateUnsavedChanges() } }
    
    // Store
    @Published var selectedStoreID: String = "main_store" { didSet { updateUnsavedChanges() } }
    @Published var selectedStoreName: String = "" { didSet { updateUnsavedChanges() } }
    @Published var availableStores: [(id: String, name: String)] = []
    
    // Publishing / Draft
    @Published var isDraft: Bool = false { didSet { updateUnsavedChanges() } }
    
    // Images
    @Published var existingImageURLs: [String] = [] { didSet { updateUnsavedChanges() } }
    @Published var pickedImages: [UIImage] = [] { didSet { updateUnsavedChanges() } }
    @Published fileprivate var livePetUnitPhotos: [String: PPLivePetUnitPhotoDraft] = [:] {
        didSet { updateUnsavedChanges() }
    }
    private var existingImageMetadata: [[AnyHashable: Any]] = []
    private var pickedImageUploadIDs: [UUID] = []
    private var pendingUnsavedUploads: [String: UUID] = [:]
    
    // UI Lifecycle & Async States
    @Published var availableMainKinds: [MainKindsModel] = []
    @Published var isLoadingKinds: Bool = false
    @Published var kindsErrorMessage: String? = nil
    
    @Published var isSubmitting: Bool = false
    @Published var submitProgress: Double = 0.0
    @Published var saveSuccessMessage: String? = nil
    @Published var errorMessage: String? = nil
    @Published var hasUnsavedChanges: Bool = false
    @Published private(set) var hasCompletedSave: Bool = false
    @Published private(set) var pendingCatalogSyncProductID: String? = nil
    @Published private(set) var hasPendingLivePetRecovery: Bool = false
    @Published fileprivate(set) var submissionFailureKind: PPLivePetSubmissionFailureKind? = nil
    
    // Active Modals
    @Published var showImagePicker: Bool = false
    @Published var showSpeciesPicker: Bool = false
    @Published var showBreedPicker: Bool = false
    @Published var showStorePicker: Bool = false
    @Published var previewImageURL: String? = nil
    @Published var previewUIImage: UIImage? = nil
    @Published var showDiscardConfirmation: Bool = false

    private var initialSetupComplete: Bool = false
    private var isPopulatingInitialValues: Bool = true
    private var isApplyingCategoryHydration: Bool = false
    private var didScheduleSuccessfulDismissal: Bool = false
    private var standardSaveCommandID: String? = nil
    private var liveCreateCommandID = PPLivePetInventoryService.commandID("catalog-create")
    private var pendingCatalogSyncSuccessMessage: String? = nil
    private var livePetRecovery: PPLivePetMutationRecovery? = nil
    private var pendingSavedAccessoryDraft: PetAccessory? = nil

    // MARK: - Initializer

    init(
        accessory: PetAccessory?,
        showTypeRow: Bool = true,
        defaultKind: AccessKindType = .typeAccessory,
        onDismiss: @escaping () -> Void
    ) {
        self.editingAccessory = accessory
        self.showTypeRow = showTypeRow
        self.onDismiss = onDismiss
        
        let initialKind: AccessKindType
        if let acc = accessory {
            initialKind = acc.accessKindType
        } else {
            initialKind = defaultKind
        }
        self.selectedKind = initialKind
        
        populateInitialValues()
        setupStoreOptions()
        restoreLivePetRecoveryIfNeeded()
        loadMainKinds()

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MainKindsUpdatedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadMainKinds(forceServer: true)
        }
    }

    // MARK: - Populate Data

    private func populateInitialValues() {
        guard let acc = editingAccessory else {
            if let active = BranchContextStore.shared.activeBranch {
                selectedStoreID = active.branchID
                selectedStoreName = active.localizedName()
            } else {
                selectedStoreID = "main_store"
                selectedStoreName = Language.get("Main Store", alter: "المتجر الرئيسي")
            }
            initialSetupComplete = true
        isPopulatingInitialValues = false
        if editingAccessory != nil {
            loadCommerceIfAvailable()
        } else {
            ensureDefaultSingleGroup()
        }
            return
        }

        name = acc.name ?? ""
        nameEn = acc.nameEn ?? ""
        desc = acc.desc ?? ""
        descEn = acc.descEn ?? ""
        sku = acc.sku ?? ""
        barcode = acc.barcode ?? ""
        
        let price = acc.price
        if price.doubleValue > 0 {
            priceText = String(format: "%g", price.doubleValue)
        }
        if let cost = acc.costPrice, cost.doubleValue > 0 {
            costPriceText = String(format: "%g", cost.doubleValue)
        }
        if let discPercent = acc.discountPercent, discPercent.doubleValue > 0 {
            discountPercentText = String(format: "%g", discPercent.doubleValue)
        }
        if let discAmount = acc.discountAmount, discAmount.doubleValue > 0 {
            discountAmountText = String(format: "%g", discAmount.doubleValue)
        }
        if let wp = acc.wholesalePrice, wp.doubleValue > 0 {
            wholesaleEnabled = true
            wholesalePriceText = String(format: "%g", wp.doubleValue)
        }
        
        quantity = max(0, acc.quantity)
        if acc.isLivePet {
            liveInventoryMode = PPLivePetInventoryMode(rawValue: acc.inventoryMode ?? "") ?? .quantity
            if liveInventoryMode == .individual, let standardPrice = acc.standardSellingPrice, standardPrice.doubleValue > 0 {
                priceText = String(format: "%g", standardPrice.doubleValue)
            }
        }
        condition = (acc.condition == .used) ? .used : .new
        
        if isFood, let exp = acc.expiryDate {
            hasExpiryDate = true
            expiryDate = exp
        } else {
            hasExpiryDate = false
        }

        hydratePhysicalSpecs(from: acc)

        selectedStoreID = (acc.storeID ?? "").isEmpty == false ? acc.storeID! : "main_store"
        selectedStoreName = (acc.storeName ?? "").isEmpty == false ? acc.storeName! : Language.get("Main Store", alter: "المتجر الرئيسي")
        
        isDraft = !acc.active
        existingImageURLs = acc.imageURLsArray ?? []
        existingImageMetadata = alignedImageMetadata(
            urls: existingImageURLs,
            metadata: acc.imageMeta ?? []
        )

        if acc.isAllCategories {
            isAllCategoriesSelected = true
            selectedMainKinds = []
        } else if let ids = acc.petMainCategoryIDs as? [NSNumber], !ids.isEmpty {
            selectedMainKinds = Set(ids.map { $0.intValue })
            isAllCategoriesSelected = false
        } else if acc.petMainCategoryID > 0 {
            selectedMainKinds = [acc.petMainCategoryID]
            isAllCategoriesSelected = false
        }

        if acc.isAllSubCategories {
            isAllSubCategoriesSelected = true
            selectedSubKinds = []
        } else if let ids = acc.petSubCategoryIDs as? [NSNumber], !ids.isEmpty {
            selectedSubKinds = Set(ids.map { $0.intValue })
            isAllSubCategoriesSelected = false
        } else if acc.petSubCategoryID > 0 {
            selectedSubKinds = [acc.petSubCategoryID]
            isAllSubCategoriesSelected = false
        }

        isPopulatingInitialValues = false
    }

    private func hydrateWeight(from accessory: PetAccessory) {
        let supportedUnits = ["kg", "g", "L", "ml"]
        let storedUnit = supportedUnits.first {
            $0.caseInsensitiveCompare(accessory.weightUnit ?? "") == .orderedSame
        }
        let storedText = (accessory.weightText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedText = parsedWeightComponents(from: storedText)

        if let numericWeight = accessory.weight?.doubleValue,
           numericWeight.isFinite,
           numericWeight >= 0 {
            if !storedText.isEmpty, parsedText == nil, storedUnit == nil {
                // Surface malformed legacy text instead of silently inventing a unit.
                weightText = storedText
                weightUnit = "kg"
                return
            }
            weightText = canonicalDecimalText(numericWeight, maximumFractionDigits: 3)
            weightUnit = storedUnit ?? parsedText?.unit ?? "kg"
            return
        }

        guard !storedText.isEmpty else {
            weightText = ""
            weightUnit = storedUnit ?? "kg"
            return
        }

        if let parsedText {
            weightText = parsedText.amount
            weightUnit = storedUnit ?? parsedText.unit ?? "kg"
            return
        }

        // Preserve an unrecognized legacy value so validation can surface it;
        // never append another unit to malformed persisted text silently.
        weightText = storedText
        weightUnit = storedUnit ?? "kg"
    }

    private func parsedWeightComponents(from text: String) -> (amount: String, unit: String?)? {
        guard !text.isEmpty else { return nil }
        let supportedUnits = ["kg", "g", "L", "ml"]
        let pattern = #"^\s*([0-9]+(?:[\.,][0-9]+)?)\s*(kg|g|l|ml)?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let amountRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let amount = String(text[amountRange]).replacingOccurrences(of: ",", with: ".")
        guard match.range(at: 2).location != NSNotFound,
              let unitRange = Range(match.range(at: 2), in: text) else {
            return (amount, nil)
        }
        let rawUnit = String(text[unitRange])
        if rawUnit.caseInsensitiveCompare("l") == .orderedSame {
            return (amount, "L")
        }
        let unit = supportedUnits.first {
            $0.caseInsensitiveCompare(rawUnit) == .orderedSame
        }
        return (amount, unit)
    }

    private func hydratePhysicalSpecs(from accessory: PetAccessory) {
        if isFood {
            physicalSpecMode = .weightVolume
            hydrateWeight(from: accessory)
            dimensionWidthText = ""
            dimensionHeightText = ""
            size = ""
            return
        }

        // 1. Direct dimension properties from accessory
        if let w = accessory.dimensionWidth?.doubleValue, let h = accessory.dimensionHeight?.doubleValue, w > 0 || h > 0 {
            physicalSpecMode = .dimensions
            dimensionWidthText = w > 0 ? canonicalDecimalText(w, maximumFractionDigits: 2) : ""
            dimensionHeightText = h > 0 ? canonicalDecimalText(h, maximumFractionDigits: 2) : ""
            let u = (accessory.dimensionUnit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            dimensionUnit = u.isEmpty ? "cm" : u
            size = ""
            weightText = ""
            return
        }

        // 2. Dimensions pattern in size string (e.g. "60 × 40 cm", "80x50 cm", "100 * 60 سم", etc.)
        if let rawSize = accessory.size, let parsed = parseDimensionsPattern(rawSize) {
            physicalSpecMode = .dimensions
            dimensionWidthText = parsed.width
            dimensionHeightText = parsed.height
            dimensionUnit = parsed.unit
            size = ""
            weightText = ""
            return
        }

        // 3. Weight/Volume present
        let trimmedWeight = (accessory.weightText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWeight.isEmpty || (accessory.weight?.doubleValue ?? 0) > 0 {
            physicalSpecMode = .weightVolume
            hydrateWeight(from: accessory)
            size = ""
            dimensionWidthText = ""
            dimensionHeightText = ""
            return
        }

        // 4. Standard apparel size present
        let trimmedSize = (accessory.size ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSize.isEmpty {
            physicalSpecMode = .standardSize
            size = trimmedSize
            dimensionWidthText = ""
            dimensionHeightText = ""
            weightText = ""
            return
        }

        // 5. Unspecified
        physicalSpecMode = .none
        size = ""
        dimensionWidthText = ""
        dimensionHeightText = ""
        weightText = ""
    }

    private func parseDimensionsPattern(_ text: String) -> (width: String, height: String, unit: String)? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "*", with: "x")
            .replacingOccurrences(of: "X", with: "x")
        let pattern = #"^\s*([0-9]+(?:[\.,][0-9]+)?)\s*x\s*([0-9]+(?:[\.,][0-9]+)?)\s*(cm|m|in|mm|سم|متر|بوصة|ملم)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: clean, range: NSRange(location: 0, length: clean.utf16.count)) else {
            return nil
        }
        guard let wRange = Range(match.range(at: 1), in: clean),
              let hRange = Range(match.range(at: 2), in: clean) else { return nil }
        let w = String(clean[wRange]).replacingOccurrences(of: ",", with: ".").normalizedEnglishDigits
        let h = String(clean[hRange]).replacingOccurrences(of: ",", with: ".").normalizedEnglishDigits
        var unit = "cm"
        if match.range(at: 3).location != NSNotFound, let uRange = Range(match.range(at: 3), in: clean) {
            let u = String(clean[uRange]).lowercased()
            if u == "m" || u == "متر" || u == "م" { unit = "m" }
            else if u == "in" || u == "بوصة" { unit = "in" }
            else if u == "mm" || u == "ملم" { unit = "mm" }
            else { unit = "cm" }
        }
        return (w, h, unit)
    }

    private func finishInitialHydration() {
        guard !initialSetupComplete else { return }
        initialSetupComplete = true
    }

    private func setupStoreOptions() {
        var options: [(id: String, name: String)] = []
        let branches = BranchContextStore.shared.availableBranches
        if !branches.isEmpty {
            for b in branches {
                options.append((b.branchID, b.localizedName()))
            }
        } else {
            let mainName = Language.get("Main Store", alter: "المتجر الرئيسي")
            options.append(("main_store", mainName))
        }
        
        if let existingID = editingAccessory?.storeID, !existingID.isEmpty, !options.contains(where: { $0.id == existingID }) {
            let existingName = editingAccessory?.storeName ?? existingID
            options.append((existingID, existingName))
        }
        
        self.availableStores = options
        
        if selectedStoreName.isEmpty || selectedStoreName == Language.get("Main Store", alter: "المتجر الرئيسي") || selectedStoreName == "Pure Pets" {
            if let matched = options.first(where: { $0.id == selectedStoreID }) {
                selectedStoreName = matched.name
            } else if let active = BranchContextStore.shared.activeBranch {
                selectedStoreID = active.branchID
                selectedStoreName = active.localizedName()
            } else {
                selectedStoreName = options.first?.name ?? Language.get("Main Store", alter: "المتجر الرئيسي")
            }
        } else if let matched = options.first(where: { $0.id == selectedStoreID }) {
            selectedStoreName = matched.name
        }
    }

    // MARK: - MainKinds & Breeds Fetching

    func loadMainKinds(forceServer: Bool = true) {
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            self.matchSelectedCategories()
            self.finishInitialHydration()
            if !forceServer {
                return
            }
        }

        isLoadingKinds = availableMainKinds.isEmpty
        kindsErrorMessage = nil

        let db = Firestore.firestore()
        let query = db.collection("MainKindsCollection").order(by: "sortingKey", descending: false)

        query.getDocuments(source: .server) { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingKinds = false

                if let error = error {
                    if self.availableMainKinds.isEmpty {
                        query.getDocuments { cacheSnap, cacheErr in
                            DispatchQueue.main.async {
                                if let docs = cacheSnap?.documents, !docs.isEmpty {
                                    self.processFreshMainKinds(docs: docs)
                                } else {
                                    self.kindsErrorMessage = error.localizedDescription
                                }
                                self.finishInitialHydration()
                            }
                        }
                    } else {
                        self.finishInitialHydration()
                    }
                    return
                }

                if let docs = snapshot?.documents, !docs.isEmpty {
                    self.processFreshMainKinds(docs: docs)
                }
                self.finishInitialHydration()
            }
        }
    }

    private func processFreshMainKinds(docs: [QueryDocumentSnapshot]) {
        var list: [MainKindsModel] = []
        for doc in docs {
            let model = MainKindsModel(snapshot: doc)
            list.append(model)
        }
        self.availableMainKinds = list
        AppManager.shared().mainKindsArray = NSMutableArray(array: list)

        if let currentMain = self.selectedMainKind {
            if let freshMain = list.first(where: { $0.id == currentMain.id }) {
                self.selectedMainKind = freshMain
                self.fetchFreshSubKinds(for: freshMain)
            }
        }
        self.matchSelectedCategories()
    }

    func fetchFreshSubKinds(for mainKind: MainKindsModel) {
        let docID = mainKind.documentID.isEmpty ? "\(mainKind.id)" : mainKind.documentID
        guard !docID.isEmpty else { return }
        let db = Firestore.firestore()

        db.collection("MainKindsCollection").document(docID).collection("SubKinds").order(by: "ID", descending: false).getDocuments(source: .server) { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var items: [SubKindModel] = []
                if let docs = snapshot?.documents, !docs.isEmpty {
                    for doc in docs {
                        let sub = SubKindModel(snapshot: doc)
                        sub.documentID = doc.documentID
                        if sub.mainKindID == 0 {
                            sub.mainKindID = mainKind.id
                        }
                        items.append(sub)
                    }
                }

                if items.isEmpty, let arr = mainKind.subKindsArray as? [SubKindModel], !arr.isEmpty {
                    items = arr
                }

                if !items.isEmpty {
                    mainKind.subKindsArray = NSMutableArray(array: items)
                    self.dynamicSubKindsByMainKind[mainKind.id] = items
                    if self.selectedMainKinds.count <= 1 && !self.isAllCategoriesSelected {
                        self.dynamicSubKinds = items
                    }
                    if let sel = self.selectedSubKind {
                        self.selectedSubKind = items.first(where: { $0.id == sel.id })
                    }
                    self.objectWillChange.send()
                }
            }
        }
    }

    func fetchFreshSubKindsForSelectedCategories() {
        let targets: [MainKindsModel]
        if isAllCategoriesSelected {
            targets = availableMainKinds
        } else if !selectedMainKinds.isEmpty {
            targets = availableMainKinds.filter { selectedMainKinds.contains($0.id) }
        } else if let main = selectedMainKind {
            targets = [main]
        } else {
            targets = []
        }
        for target in targets {
            fetchFreshSubKinds(for: target)
        }
    }

    func fetchSubSubTaxonomy(for subKind: SubKindModel?) {
        guard let subKind = subKind else {
            self.availableSubSubKinds = []
            self.subSubKindItemsBySubSubID = [:]
            return
        }

        // Fast-path: check if subKind in-memory model already has subSubKindArray
        if let arr = subKind.subSubKindArray as? [subSubKindModel], !arr.isEmpty {
            self.availableSubSubKinds = arr.map { m in
                AdminSubSubKindItem(
                    id: "\(m.id)",
                    numericID: m.id,
                    subKindID: m.subKindID,
                    nameAr: m.nameAr ?? "",
                    nameEn: m.nameEn ?? "",
                    imageUrl: ""
                )
            }
            for m in arr {
                if let items = m.subKindItemsArray as? [subKindItemsModel], !items.isEmpty {
                    self.subSubKindItemsBySubSubID[m.id] = items.map { it in
                        AdminSubKindItemDetail(
                            id: "\(it.id)",
                            numericID: it.id,
                            subSubKindID: it.subSubKindID,
                            itemNameAr: it.itemNameAr ?? "",
                            itemNameEn: it.itemNameEn ?? "",
                            male: it.male ?? "",
                            female: it.female ?? "",
                            imageUrl: ""
                        )
                    }
                }
            }
        }

        let mainKind = selectedMainKind ?? availableMainKinds.first(where: { $0.id == subKind.mainKindID })
        guard let mainKind = mainKind else { return }
        let mainDocID = mainKind.documentID.isEmpty ? "\(mainKind.id)" : mainKind.documentID
        guard !mainDocID.isEmpty else { return }

        let db = Firestore.firestore()
        let subKindDocID = (subKind.documentID != nil && !subKind.documentID!.isEmpty) ? subKind.documentID! : "\(subKind.id)"

        isLoadingSubSubTaxonomy = true

        let loadSubSubsForSubRef: (DocumentReference) -> Void = { [weak self] subDocRef in
            subDocRef.collection("SubSubKinds").order(by: "ID", descending: false).getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoadingSubSubTaxonomy = false
                    guard let docs = snapshot?.documents, !docs.isEmpty else { return }
                    let subSubs = docs.compactMap { AdminSubSubKindItem.fromSnapshot($0) }
                    if !subSubs.isEmpty {
                        self.availableSubSubKinds = subSubs
                        for subSub in subSubs {
                            let subSubDocID = subSub.id.isEmpty ? "\(subSub.numericID)" : subSub.id
                            subDocRef.collection("SubSubKinds").document(subSubDocID).collection("Items").order(by: "ID", descending: false).getDocuments { itemSnap, _ in
                                DispatchQueue.main.async {
                                    let items = itemSnap?.documents.compactMap { AdminSubKindItemDetail.fromSnapshot($0) } ?? []
                                    self.subSubKindItemsBySubSubID[subSub.numericID] = items
                                }
                            }
                        }
                    }
                }
            }
        }

        let mainRef = db.collection("MainKindsCollection").document(mainDocID)
        let directSubRef = mainRef.collection("SubKinds").document(subKindDocID)

        directSubRef.getDocument { [weak self] snap, _ in
            if let snap = snap, snap.exists {
                loadSubSubsForSubRef(directSubRef)
            } else {
                mainRef.collection("SubKinds").whereField("ID", isEqualTo: subKind.id).getDocuments { subSnap, _ in
                    if let doc = subSnap?.documents.first {
                        loadSubSubsForSubRef(doc.reference)
                    } else {
                        DispatchQueue.main.async {
                            self?.isLoadingSubSubTaxonomy = false
                        }
                    }
                }
            }
        }
    }

    private func matchSelectedCategories() {
        let wasTrackingChanges = initialSetupComplete
        let wasDirty = hasUnsavedChanges
        let wasApplyingHydration = isApplyingCategoryHydration
        initialSetupComplete = false
        isApplyingCategoryHydration = true
        defer {
            initialSetupComplete = wasTrackingChanges
            isApplyingCategoryHydration = wasApplyingHydration
            hasUnsavedChanges = wasDirty
        }

        guard let acc = editingAccessory else { return }
        if acc.isAllCategories {
            self.isAllCategoriesSelected = true
            self.selectedMainKinds = []
            self.selectedMainKind = nil
        } else if let ids = acc.petMainCategoryIDs as? [NSNumber], !ids.isEmpty {
            self.selectedMainKinds = Set(ids.map { $0.intValue })
            self.isAllCategoriesSelected = false
            if let firstID = ids.first?.intValue {
                self.selectedMainKind = availableMainKinds.first(where: { $0.id == firstID })
            }
        } else if acc.petMainCategoryID > 0 {
            if let matchedMain = availableMainKinds.first(where: { $0.id == acc.petMainCategoryID }) {
                self.selectedMainKind = matchedMain
                self.selectedMainKinds = [acc.petMainCategoryID]
                self.isAllCategoriesSelected = false
            }
        }

        if acc.isAllSubCategories {
            self.isAllSubCategoriesSelected = true
            self.selectedSubKinds = []
            self.selectedSubKind = nil
        } else if let ids = acc.petSubCategoryIDs as? [NSNumber], !ids.isEmpty {
            self.selectedSubKinds = Set(ids.map { $0.intValue })
            self.isAllSubCategoriesSelected = false
            if let firstID = ids.first?.intValue {
                self.selectedSubKind = availableSubKinds.first(where: { $0.id == firstID })
            }
        } else if acc.petSubCategoryID > 0 {
            self.selectedSubKinds = [acc.petSubCategoryID]
            self.isAllSubCategoriesSelected = false
            if let subList = selectedMainKind?.subKindsArray as? [SubKindModel] {
                self.selectedSubKind = subList.first(where: { $0.id == acc.petSubCategoryID })
            }
        }
    }

    // MARK: - Computed Properties

    var isFood: Bool { selectedKind == .typeFood }
    var isLivePet: Bool { selectedKind == .typeLivePets }
    var isEditingLivePet: Bool { isLivePet && editingAccessory != nil }
    var isIndividualLivePet: Bool { isLivePet && liveInventoryMode == .individual }
    var isAwaitingCatalogSync: Bool { pendingCatalogSyncProductID != nil }
    private var preventsExplicitDismissal: Bool {
        isSubmitting || hasPendingLivePetRecovery || hasCompletedSave
    }
    var blocksDismissal: Bool {
        preventsExplicitDismissal || !pickedImageUploadIDs.isEmpty || !pendingUnsavedUploads.isEmpty
    }
    var canManageStock: Bool {
        PPStaffAuth.shared().cachedCurrentStaff?.hasPermission("stock.manage") ?? false
    }
    var canViewStockCosts: Bool {
        canManageStock || (PPStaffAuth.shared().cachedCurrentStaff?.hasPermission("stock.view") ?? false) || (PPStaffAuth.shared().cachedCurrentStaff?.hasPermission("stock.cost.view") ?? false)
    }

    var canManagePricing: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return true }
        if staff.isAdmin() { return true }
        return staff.hasPermission("catalog.pricing.manage") || canManageStock
    }

    var canManageWholesale: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return true }
        if staff.isAdmin() { return true }
        if staff.hasPermission("catalog.wholesale.manage") { return true }
        return canManageStock || canManagePricing
    }

    func ensureDefaultSingleGroup() {
        if quantityGroups.isEmpty {
            let single = PPQuantityGroupDraft(
                id: "single",
                nameAr: "حبة",
                nameEn: "Single",
                unitsPerGroup: 1,
                barcode: barcode,
                sku: sku,
                sortOrder: 0,
                retailEnabled: true,
                wholesaleEnabled: wholesaleEnabled,
                retailPriceText: priceText,
                wholesalePriceText: wholesalePriceText,
                defaultForRetail: true,
                defaultForWholesale: wholesaleEnabled,
                active: true
            )
            quantityGroups = [single]
        }
    }

    func syncBasePriceToSingleGroup() {
        if let idx = quantityGroups.firstIndex(where: { $0.unitsPerGroup == 1 && $0.defaultForRetail }) {
            quantityGroups[idx].retailPriceText = priceText
            if !barcode.isEmpty && quantityGroups[idx].barcode.isEmpty {
                quantityGroups[idx].barcode = barcode
            }
        }
    }

    func syncWholesaleStateToSingleGroup() {
        if let idx = quantityGroups.firstIndex(where: { $0.defaultForRetail || $0.unitsPerGroup == 1 }) {
            quantityGroups[idx].wholesaleEnabled = wholesaleEnabled
            if wholesaleEnabled {
                quantityGroups[idx].wholesalePriceText = wholesalePriceText
                quantityGroups[idx].defaultForWholesale = true
            }
        }
    }

    func syncWholesalePriceToGroups() {
        if let idx = quantityGroups.firstIndex(where: { $0.defaultForWholesale && $0.wholesaleEnabled }) {
            quantityGroups[idx].wholesalePriceText = wholesalePriceText
        } else if wholesaleEnabled, let firstW = quantityGroups.firstIndex(where: { $0.wholesaleEnabled }) {
            quantityGroups[firstW].wholesalePriceText = wholesalePriceText
        }
    }

    func saveQuantityGroup(_ group: PPQuantityGroupDraft) {
        if let idx = quantityGroups.firstIndex(where: { $0.id == group.id }) {
            quantityGroups[idx] = group
        } else {
            quantityGroups.append(group)
        }
        if group.defaultForRetail {
            for i in 0..<quantityGroups.count {
                if quantityGroups[i].id != group.id {
                    quantityGroups[i].defaultForRetail = false
                }
            }
        }
        if group.defaultForWholesale {
            for i in 0..<quantityGroups.count {
                if quantityGroups[i].id != group.id {
                    quantityGroups[i].defaultForWholesale = false
                }
            }
        }
        showQuantityGroupInspector = false
        selectedQuantityGroupForEditing = nil
        updateUnsavedChanges()
    }

    func deleteQuantityGroup(id: String) {
        guard quantityGroups.count > 1 else { return }
        quantityGroups.removeAll(where: { $0.id == id })
        if !quantityGroups.contains(where: { $0.defaultForRetail }) {
            if let first = quantityGroups.firstIndex(where: { $0.retailEnabled }) {
                quantityGroups[first].defaultForRetail = true
            }
        }
        showQuantityGroupInspector = false
        selectedQuantityGroupForEditing = nil
        updateUnsavedChanges()
    }

    func validateQuantityGroups() -> (isValid: Bool, message: String?) {
        guard !isLivePet else { return (true, nil) }
        ensureDefaultSingleGroup()

        for g in quantityGroups {
            if g.unitsPerGroup < 1 {
                return (false, Language.get("Validation_Group_Units_Positive", alter: "يجب أن تكون كمية المجموعة عدداً صحيحاً أكبر من صفر."))
            }
            if g.retailEnabled && (g.retailPrice <= 0 || !g.retailPrice.isFinite) {
                return (false, String(format: Language.get("Validation_Group_Retail_Price_Required", alter: "يرجى تحديد سعر تجزئة صالح للوحدة: %@"), g.localizedName))
            }
            if g.wholesaleEnabled && (g.wholesalePrice <= 0 || !g.wholesalePrice.isFinite) {
                return (false, String(format: Language.get("Validation_Group_Wholesale_Price_Required", alter: "يرجى تحديد سعر جملة صالح للوحدة: %@"), g.localizedName))
            }
            if g.defaultForRetail && !g.retailEnabled {
                return (false, Language.get("Validation_Default_Retail_Disabled", alter: "لا يمكن تعيين الوحدة كافتراضية للتجزئة وهي معطلة للتجزئة."))
            }
            if g.defaultForWholesale && !g.wholesaleEnabled {
                return (false, Language.get("Validation_Default_Wholesale_Disabled", alter: "لا يمكن تعيين الوحدة كافتراضية للجملة وهي معطلة للجملة."))
            }
        }

        let ids = quantityGroups.map { $0.id }
        if Set(ids).count != ids.count {
            return (false, Language.get("Validation_Group_Duplicate_ID", alter: "توجد وحدات بيع بمعرفات مكررة."))
        }

        let barcodes = quantityGroups.map { $0.barcode.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if Set(barcodes).count != barcodes.count {
            return (false, Language.get("Validation_Group_Duplicate_Barcode", alter: "لا يمكن استخدام نفس الباركود لأكثر من وحدة بيع."))
        }

        let retailDefaults = quantityGroups.filter { $0.defaultForRetail && $0.retailEnabled && $0.active }
        if retailDefaults.count > 1 {
            return (false, Language.get("Validation_Multiple_Retail_Defaults", alter: "يمكن تحديد وحدة بيع افتراضية واحدة فقط للتجزئة."))
        }

        let wholesaleDefaults = quantityGroups.filter { $0.defaultForWholesale && $0.wholesaleEnabled && $0.active }
        if wholesaleDefaults.count > 1 {
            return (false, Language.get("Validation_Multiple_Wholesale_Defaults", alter: "يمكن تحديد وحدة بيع افتراضية واحدة فقط للجملة."))
        }

        return (true, nil)
    }

    var defaultRetailGroupSummary: String {
        if let g = quantityGroups.first(where: { $0.defaultForRetail && $0.retailEnabled }) ?? quantityGroups.first(where: { $0.retailEnabled }) {
            return "\(g.localizedName) · \(String(format: "%.0f", g.retailPrice)) \(Language.get("QAR", alter: "ر.ق"))"
        }
        return "\(basePrice) \(Language.get("QAR", alter: "ر.ق"))"
    }

    var defaultWholesaleGroupSummary: String? {
        guard wholesaleEnabled else { return nil }
        if let g = quantityGroups.first(where: { $0.defaultForWholesale && $0.wholesaleEnabled }) ?? quantityGroups.first(where: { $0.wholesaleEnabled }) {
            let countStr = g.unitsPerGroup > 1 ? " ×\(g.unitsPerGroup)" : ""
            return "\(g.localizedName)\(countStr) · \(String(format: "%.0f", g.wholesalePrice)) \(Language.get("QAR", alter: "ر.ق"))"
        }
        return nil
    }

    func loadCommerceIfAvailable() {
        guard let acc = editingAccessory, !acc.accessoryID.isEmpty, !isIndividualLivePet else {
            ensureDefaultSingleGroup()
            return
        }
        let accID = acc.accessoryID
        if let wp = acc.wholesalePrice, wp.doubleValue > 0 {
            wholesaleEnabled = true
            wholesalePriceText = String(format: "%g", wp.doubleValue)
        }
        isLoadingCommerce = true
        Functions.functions().httpsCallable("getProductCommerce").call(["productId": accID]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingCommerce = false
                guard let data = result?.data as? [String: Any],
                      let commerce = data["productCommerce"] as? [String: Any] else {
                    self.ensureDefaultSingleGroup()
                    return
                }

                if let rev = commerce["pricingRevision"] as? Int {
                    self.pricingRevision = rev
                }
                if let base = commerce["baseUnit"] as? [String: Any] {
                    self.commerceBaseUnitID = base["id"] as? String ?? "piece"
                    self.commerceBaseUnitNameAr = base["nameAr"] as? String ?? "قطعة"
                    self.commerceBaseUnitNameEn = base["nameEn"] as? String ?? "Piece"
                }
                if let rawGroups = commerce["quantityGroups"] as? [[String: Any]], !rawGroups.isEmpty {
                    self.quantityGroups = rawGroups.map { g in
                        let retailMinor = g["retailPriceMinor"] as? Int ?? 0
                        let wholesaleMinor = g["wholesalePriceMinor"] as? Int
                        let wEnabled = g["wholesaleEnabled"] as? Bool ?? false
                        return PPQuantityGroupDraft(
                            id: g["id"] as? String ?? UUID().uuidString,
                            nameAr: g["nameAr"] as? String ?? "",
                            nameEn: g["nameEn"] as? String ?? "",
                            unitsPerGroup: max(1, g["unitsPerGroup"] as? Int ?? 1),
                            barcode: g["barcode"] as? String ?? "",
                            sku: g["sku"] as? String ?? "",
                            sortOrder: g["sortOrder"] as? Int ?? 0,
                            retailEnabled: g["retailEnabled"] as? Bool ?? true,
                            wholesaleEnabled: wEnabled,
                            retailPriceText: String(format: "%.2f", Double(retailMinor) / 100.0),
                            wholesalePriceText: wholesaleMinor != nil ? String(format: "%.2f", Double(wholesaleMinor!) / 100.0) : "",
                            defaultForRetail: g["defaultForRetail"] as? Bool ?? false,
                            defaultForWholesale: g["defaultForWholesale"] as? Bool ?? false,
                            active: g["active"] as? Bool ?? true
                        )
                    }
                    if self.quantityGroups.contains(where: { $0.wholesaleEnabled }) {
                        self.wholesaleEnabled = true
                        if let defaultW = self.quantityGroups.first(where: { $0.defaultForWholesale && $0.wholesaleEnabled }) {
                            self.wholesalePriceText = defaultW.wholesalePriceText
                        }
                    }
                } else {
                    self.ensureDefaultSingleGroup()
                }
            }
        }
    }

    func persistCommerceRecord(for productID: String) {
        guard !isIndividualLivePet, !productID.isEmpty else { return }
        ensureDefaultSingleGroup()

        let groupsPayload: [[String: Any]] = quantityGroups.map { g in
            var dict: [String: Any] = [
                "id": g.id,
                "nameAr": g.nameAr.isEmpty ? (Language.isRTL() ? "وحدة" : "Unit") : g.nameAr,
                "nameEn": g.nameEn.isEmpty ? "Unit" : g.nameEn,
                "unitsPerGroup": max(1, g.unitsPerGroup),
                "barcode": g.barcode.isEmpty ? NSNull() : g.barcode,
                "sku": g.sku.isEmpty ? NSNull() : g.sku,
                "sortOrder": g.sortOrder,
                "retailEnabled": g.retailEnabled,
                "wholesaleEnabled": g.wholesaleEnabled,
                "retailPriceMinor": g.retailPriceMinor,
                "wholesalePriceMinor": g.wholesaleEnabled ? (g.wholesalePriceMinor as Any) : NSNull(),
                "defaultForRetail": g.defaultForRetail,
                "defaultForWholesale": g.defaultForWholesale,
                "active": g.active
            ]
            return dict
        }

        let payload: [String: Any] = [
            "productId": productID,
            "commandId": "cmd_comm_\(UUID().uuidString)",
            "currency": "QAR",
            "expectedRevision": pricingRevision,
            "baseUnit": [
                "id": commerceBaseUnitID,
                "nameAr": commerceBaseUnitNameAr,
                "nameEn": commerceBaseUnitNameEn
            ],
            "quantityGroups": groupsPayload
        ]

        Functions.functions().httpsCallable("upsertProductCommerce").call(["payload": payload]) { [weak self] result, error in
            if let err = error {
                print("[PPAccessoryEditorView] upsertProductCommerce error:", err.localizedDescription)
                DispatchQueue.main.async {
                    PPHUD.showError(
                        Language.get("CommercePricingError", alter: "تنبيه التسعير"),
                        subtitle: err.localizedDescription
                    )
                }
            } else if let data = result?.data as? [String: Any], let rev = data["pricingRevision"] as? Int {
                DispatchQueue.main.async {
                    self?.pricingRevision = rev
                }
            }
        }
    }

    var groupCost: Double {
        let clean = liveGroupCostText.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return max(0, Double(clean) ?? 0)
    }

    // MARK: - Unit Operations & Smart Clone

    func addLivePetUnit() {
        guard !isEditingLivePet, livePetUnits.count < 100 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // A batch is usually same-sex, so the previous animal's gender is a far
        // better starting point than a blank one. It stays fully editable.
        livePetUnits.append(PPLivePetUnitDraft(
            gender: livePetUnits.last?.gender ?? .unspecified,
            sellingPriceText: priceText,
            supplier: liveSupplier,
            subSubKindID: livePetUnits.last?.subSubKindID,
            subSubKindNameAr: livePetUnits.last?.subSubKindNameAr,
            subSubKindNameEn: livePetUnits.last?.subSubKindNameEn,
            subSubKindItemID: livePetUnits.last?.subSubKindItemID,
            subSubKindItemNameAr: livePetUnits.last?.subSubKindItemNameAr,
            subSubKindItemNameEn: livePetUnits.last?.subSubKindItemNameEn
        ))
        quantity = livePetUnits.count
    }

    /// Rewrites one animal's gender in place. Kept on the view model so the
    /// selector stays a pure projection of state and the unsaved-changes signal
    /// fires through the same `livePetUnits` `didSet` as every other field.
    func setLivePetUnitGender(_ gender: PPLivePetUnitGender, unitID: String) {
        guard !isEditingLivePet,
              let index = livePetUnits.firstIndex(where: { $0.id == unitID }),
              livePetUnits[index].gender != gender else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        livePetUnits[index].gender = gender
    }

    func setLivePetUnitSubSubKind(_ subSub: AdminSubSubKindItem?, unitID: String) {
        guard !isEditingLivePet,
              let index = livePetUnits.firstIndex(where: { $0.id == unitID }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        livePetUnits[index].subSubKindID = subSub?.numericID
        livePetUnits[index].subSubKindNameAr = subSub?.nameAr
        livePetUnits[index].subSubKindNameEn = subSub?.nameEn
        // Reset subSubKindItem when subSubKind changes
        livePetUnits[index].subSubKindItemID = nil
        livePetUnits[index].subSubKindItemNameAr = nil
        livePetUnits[index].subSubKindItemNameEn = nil
    }

    func setLivePetUnitSubSubKindItem(_ item: AdminSubKindItemDetail?, unitID: String) {
        guard !isEditingLivePet,
              let index = livePetUnits.firstIndex(where: { $0.id == unitID }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        livePetUnits[index].subSubKindItemID = item?.numericID
        livePetUnits[index].subSubKindItemNameAr = item?.itemNameAr
        livePetUnits[index].subSubKindItemNameEn = item?.itemNameEn
    }

    /// Ring/tag keys that appear more than once in the current draft set.
    ///
    /// Mirrors the server's `ringTagKey` normalization so a collision surfaces
    /// while the operator is still typing instead of as an `already-exists`
    /// rejection after submission. This never replaces the server check.
    var duplicateRingTagKeys: Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for unit in livePetUnits {
            let key = PPAccessoryEditorViewModel.ringTagKey(unit.ringTag)
            guard !key.isEmpty else { continue }
            if seen.contains(key) { duplicates.insert(key) } else { seen.insert(key) }
        }
        return duplicates
    }

    static func ringTagKey(_ raw: String) -> String {
        raw.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    func clonePreviousUnit(from unit: PPLivePetUnitDraft) {
        guard !isEditingLivePet, livePetUnits.count < 100 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Smart auto-increment of sequential digits in ring tag
        var nextRing = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"(\d+)$"#),
           let match = regex.firstMatch(in: nextRing, range: NSRange(nextRing.startIndex..., in: nextRing)),
           let range = Range(match.range(at: 1), in: nextRing) {
            let digitStr = String(nextRing[range])
            if let num = Int(digitStr) {
                let nextNumStr = String(format: "%0\(digitStr.count)d", num + 1)
                nextRing.replaceSubrange(range, with: nextNumStr)
            }
        }

        let cloned = PPLivePetUnitDraft(
            ringTag: nextRing,
            gender: unit.gender,
            acquisitionDate: unit.acquisitionDate,
            purchaseCostText: unit.purchaseCostText,
            sellingPriceText: unit.sellingPriceText.isEmpty ? priceText : unit.sellingPriceText,
            supplier: unit.supplier,
            notes: unit.notes,
            subSubKindID: unit.subSubKindID,
            subSubKindNameAr: unit.subSubKindNameAr,
            subSubKindNameEn: unit.subSubKindNameEn,
            subSubKindItemID: unit.subSubKindItemID,
            subSubKindItemNameAr: unit.subSubKindItemNameAr,
            subSubKindItemNameEn: unit.subSubKindItemNameEn
        )
        livePetUnits.append(cloned)
        quantity = livePetUnits.count
    }

    func removeLivePetUnit(id: String) {
        guard !isEditingLivePet, livePetUnits.count > 1 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        livePetUnitPhotos.removeValue(forKey: id)
        livePetUnits.removeAll { $0.id == id }
        quantity = livePetUnits.count
    }

    func selectLiveInventoryMode(_ mode: PPLivePetInventoryMode) {
        guard !isEditingLivePet else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        liveInventoryMode = mode
        if mode == .individual {
            if livePetUnits.isEmpty {
                livePetUnits = [PPLivePetUnitDraft(sellingPriceText: priceText, supplier: liveSupplier)]
            }
            quantity = livePetUnits.count
        }
    }

    // MARK: - Stage Completeness & Validation Radar

    func isStageComplete(_ stage: PPEditorStage) -> Bool {
        switch stage {
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedMainKind != nil
        case .bioVault:
            if !isLivePet { return true }
            if liveInventoryMode == .individual {
                if isEditingLivePet { return true }
                guard !livePetUnits.isEmpty,
                      livePetUnits.allSatisfy({ !$0.ringTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    return false
                }
                // A duplicate ring/tag is a guaranteed `already-exists` rejection
                // server-side, so the stage is not complete while one exists.
                return duplicateRingTagKeys.isEmpty
            }
            return quantity >= 1
        case .pricing:
            return basePrice > 0
        case .governance:
            return !selectedStoreID.isEmpty
        }
    }

    var missingRequirementHint: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return Language.get("NameRequiredHint", alter: "أدخل اسم الصنف أولاً")
        }
        if selectedMainKind == nil {
            return Language.get("SpeciesRequiredHint", alter: "اختر نوع وفئة الحيوان")
        }
        if basePrice <= 0 {
            return Language.get("PriceRequiredHint", alter: "حدد سعر البيع القياسي")
        }
        if isIndividualLivePet {
            let emptyRings = livePetUnits.filter { $0.ringTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !emptyRings.isEmpty {
                return Language.get("RingRequiredHint", alter: "استكمل أرقام الحلقات/الشرائح للحيوانات")
            }
            if !duplicateRingTagKeys.isEmpty {
                return Language.get("RingDuplicateHint", alter: "رقم حلقة أو شريحة مكرر بين الحيوانات")
            }
        }
        return nil
    }

    // MARK: - Profit & Margin Telemetry

    var profitMarginTelemetry: (marginPercent: Double, netProfit: Double)? {
        guard canViewStockCosts else { return nil }

        if isIndividualLivePet {
            let validatedPairs = livePetUnits.compactMap { unit -> (sellingPrice: Double, purchaseCost: Double)? in
                let sellingText = unit.sellingPriceText.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let costText = unit.purchaseCostText.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let sellingPrice = Double(sellingText), sellingPrice > 0,
                      let purchaseCost = Double(costText), purchaseCost >= 0 else {
                    return nil
                }
                return (sellingPrice, purchaseCost)
            }
            guard !validatedPairs.isEmpty, validatedPairs.count == livePetUnits.count else { return nil }
            let totalSellingPrice = validatedPairs.reduce(0) { $0 + $1.sellingPrice }
            let totalPurchaseCost = validatedPairs.reduce(0) { $0 + $1.purchaseCost }
            guard totalSellingPrice > 0, totalPurchaseCost > 0 else { return nil }
            let netProfit = totalSellingPrice - totalPurchaseCost
            return ((netProfit / totalSellingPrice) * 100.0, netProfit)
        }

        guard isLivePet, liveInventoryMode == .quantity, calculatedFinalPrice > 0, groupCost > 0 else {
            return nil
        }
        let netProfit = calculatedFinalPrice - groupCost
        return ((netProfit / calculatedFinalPrice) * 100.0, netProfit)
    }

    var screenTitle: String {
        if editingAccessory != nil {
            if isFood { return Language.get("Edit Food", alter: "تعديل بيانات الغذاء") }
            if isLivePet { return Language.get("Edit Live Pet", alter: "تعديل بيانات الحيوان الأليف") }
            return Language.get("Edit Accessory", alter: "تعديل بيانات المنتج")
        }
        if isFood { return Language.get("Add Food", alter: "إضافة غذاء أو مكمل غذائي") }
        if isLivePet { return Language.get("Add Live Pet", alter: "تسجيل حيوان أليف جديد") }
        return Language.get("Add Accessory", alter: "إضافة منتج أو إكسسوار جديد")
    }

    var eyebrowKindText: String {
        if isFood { return Language.get("Food", alter: "أغذية ومكملات") }
        if isLivePet { return Language.get("Live pets", alter: "حيوانات حية") }
        return Language.get("Accessory", alter: "إكسسوارات ومستلزمات")
    }

    var totalImageCount: Int {
        existingImageURLs.count + pickedImages.count
    }

    var canAddImages: Bool {
        totalImageCount < 9
    }

    var availableSubKinds: [SubKindModel] {
        if !isLivePet {
            if isAllCategoriesSelected {
                var aggregated: [SubKindModel] = []
                var seenKeys = Set<String>()
                for kind in availableMainKinds {
                    let subs = dynamicSubKindsByMainKind[kind.id] ?? (kind.subKindsArray as? [SubKindModel]) ?? []
                    for sub in subs {
                        if sub.mainKindID <= 0 {
                            sub.mainKindID = kind.id
                        }
                        let key = "\(sub.mainKindID)_\(sub.id)"
                        if !seenKeys.contains(key) {
                            seenKeys.insert(key)
                            aggregated.append(sub)
                        }
                    }
                }
                return aggregated
            } else if selectedMainKinds.count > 1 {
                var aggregated: [SubKindModel] = []
                var seenKeys = Set<String>()
                for kind in availableMainKinds where selectedMainKinds.contains(kind.id) {
                    let subs = dynamicSubKindsByMainKind[kind.id] ?? (kind.subKindsArray as? [SubKindModel]) ?? []
                    for sub in subs {
                        if sub.mainKindID <= 0 {
                            sub.mainKindID = kind.id
                        }
                        let key = "\(sub.mainKindID)_\(sub.id)"
                        if !seenKeys.contains(key) {
                            seenKeys.insert(key)
                            aggregated.append(sub)
                        }
                    }
                }
                return aggregated
            } else if selectedMainKinds.count == 1, let firstID = selectedMainKinds.first {
                if let kind = availableMainKinds.first(where: { $0.id == firstID }) {
                    if let subs = dynamicSubKindsByMainKind[firstID], !subs.isEmpty {
                        return subs
                    }
                    if !dynamicSubKinds.isEmpty && selectedMainKind?.id == firstID {
                        return dynamicSubKinds
                    }
                    return (kind.subKindsArray as? [SubKindModel]) ?? []
                }
            }
        }
        if !dynamicSubKinds.isEmpty {
            return dynamicSubKinds
        }
        return (selectedMainKind?.subKindsArray as? [SubKindModel]) ?? []
    }

    var hasNoCategorySelected: Bool {
        if isLivePet {
            return selectedMainKind == nil
        }
        return !isAllCategoriesSelected && selectedMainKinds.isEmpty && selectedMainKind == nil
    }

    var selectedCategoryDisplayTitle: String? {
        if isLivePet {
            return selectedMainKind?.kindName
        }
        if isAllCategoriesSelected {
            return Language.get("CatalogIntake_AllCategoriesUniversal", alter: "جميع الفئات • لكل الحيوانات")
        }
        if !selectedMainKinds.isEmpty {
            var names: [String] = []
            for id in selectedMainKinds.sorted() {
                if let match = availableMainKinds.first(where: { $0.id == id }) {
                    names.append(match.kindName)
                } else {
                    let fallback = MainKindsModel.kindName(forID: id)
                    if !fallback.isEmpty {
                        names.append(fallback)
                    }
                }
            }
            if !names.isEmpty {
                return names.joined(separator: "، ")
            }
        }
        return selectedMainKind?.kindName
    }

    var selectedSubCategoryDisplayTitle: String? {
        if isLivePet {
            return selectedSubKind?.subKindName
        }
        if isAllSubCategoriesSelected {
            return Language.get("CatalogIntake_AllSubCategoriesUniversal", alter: "جميع التصنيفات الفرعية")
        }
        if !selectedSubKinds.isEmpty {
            var names: [String] = []
            for id in selectedSubKinds.sorted() {
                if let match = availableSubKinds.first(where: { $0.id == id }) {
                    names.append(match.subKindName)
                }
            }
            if !names.isEmpty {
                return names.joined(separator: "، ")
            }
        }
        return selectedSubKind?.subKindName
    }

    // MARK: - Pricing Calculations

    var basePrice: Double {
        decimalValue(priceText) ?? 0.0
    }

    var discountPercent: Double {
        decimalValue(discountPercentText) ?? 0.0
    }

    var discountAmount: Double {
        decimalValue(discountAmountText) ?? 0.0
    }

    func isValidDiscountPercentInput() -> Bool {
        isValidOptionalDecimal(discountPercentText, maximum: 100)
    }

    func isValidDiscountAmountInput() -> Bool {
        isValidOptionalDecimal(discountAmountText, maximum: 999_999_999.99)
    }

    func isValidWeightInput() -> Bool {
        isValidOptionalDecimal(weightText, maximum: 999_999_999.999, maximumFractionDigits: 3)
    }

    func isValidDimensionsInput() -> Bool {
        guard physicalSpecMode == .dimensions else { return true }
        let trimmedW = dimensionWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedH = dimensionHeightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedW.isEmpty && trimmedH.isEmpty { return true }
        if !isValidOptionalDecimal(dimensionWidthText, maximum: 99_999.99, maximumFractionDigits: 2) { return false }
        if !isValidOptionalDecimal(dimensionHeightText, maximum: 99_999.99, maximumFractionDigits: 2) { return false }
        return true
    }

    var calculatedFinalPrice: Double {
        guard basePrice > 0 else { return 0.0 }
        var finalVal = basePrice
        if discountPercent > 0 {
            finalVal = basePrice - (basePrice * (discountPercent / 100.0))
        }
        if discountAmount > 0 {
            finalVal -= discountAmount
        }
        return max(0.0, finalVal)
    }

    var formattedFinalPrice: String {
        formattedCurrency(calculatedFinalPrice)
    }

    var customerFacingPriceText: String {
        guard isIndividualLivePet else { return formattedFinalPrice }

        if isEditingLivePet {
            let currentMinimum = editingAccessory?.price.doubleValue ?? 0
            return currentMinimum > 0 ? formattedCurrency(currentMinimum) : "—"
        }

        let prices = livePetUnits.compactMap { unit -> Double? in
            guard let value = decimalValue(unit.sellingPriceText), value > 0 else { return nil }
            return value
        }
        guard !prices.isEmpty, prices.count == livePetUnits.count,
              let minimum = prices.min(), let maximum = prices.max() else {
            return "—"
        }
        if abs(maximum - minimum) < 0.000_001 {
            return formattedCurrency(minimum)
        }
        let currencySymbol = Language.get("QAR", alter: "ر.ق")
        return String(format: "%.2f–%.2f %@", minimum, maximum, currencySymbol).normalizedEnglishDigits
    }

    var customerFacingPriceIsResolved: Bool {
        if !isIndividualLivePet { return calculatedFinalPrice > 0 }
        if isEditingLivePet { return (editingAccessory?.price.doubleValue ?? 0) > 0 }
        return !livePetUnits.isEmpty && livePetUnits.allSatisfy {
            guard let value = decimalValue($0.sellingPriceText), value > 0 else { return false }
            return abs(value * 100 - (value * 100).rounded()) < 0.000_001
        }
    }

    private func decimalValue(_ text: String) -> Double? {
        let clean = text.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let value = Double(clean), value.isFinite else { return nil }
        return value
    }

    private func isValidOptionalDecimal(
        _ text: String,
        maximum: Double,
        maximumFractionDigits: Int = 2
    ) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return true }
        guard let value = decimalValue(clean), value >= 0, value <= maximum else { return false }
        let scale = pow(10.0, Double(maximumFractionDigits))
        return abs(value * scale - (value * scale).rounded()) < 0.000_001
    }

    private func canonicalDecimalText(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formattedCurrency(_ value: Double) -> String {
        let currencySymbol = Language.get("QAR", alter: "ر.ق")
        if value == floor(value) {
            return String(format: "%.0f %@", value, currencySymbol).normalizedEnglishDigits
        }
        return String(format: "%.2f %@", value, currencySymbol).normalizedEnglishDigits
    }

    // MARK: - Image Operations

    private func alignedImageMetadata(
        urls: [String],
        metadata: [[AnyHashable: Any]]
    ) -> [[AnyHashable: Any]] {
        urls.enumerated().map { index, url in
            var item = index < metadata.count ? metadata[index] : [:]
            item["url"] = url
            if item["width"] == nil { item["width"] = 0 }
            if item["height"] == nil { item["height"] = 0 }
            return item
        }
    }

    func addPickedImages(_ images: [UIImage]) {
        for image in images {
            guard canAddImages else { break }
            pickedImageUploadIDs.append(UUID())
            pickedImages.append(image)
        }
    }

    func removeExistingImage(at index: Int) {
        guard index >= 0 && index < existingImageURLs.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let removedURL = existingImageURLs[index]
        if let uploadID = pendingUnsavedUploads.removeValue(forKey: removedURL) {
            Storage.storage().reference()
                .child("petAccessories")
                .child("\(uploadID.uuidString).png")
                .delete { _ in }
        }
        if index < existingImageMetadata.count {
            existingImageMetadata.remove(at: index)
        }
        existingImageURLs.remove(at: index)
    }

    func removePickedImage(at index: Int) {
        guard index >= 0 && index < pickedImages.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if index < pickedImageUploadIDs.count {
            let uploadID = pickedImageUploadIDs.remove(at: index)
            Storage.storage().reference()
                .child("petAccessories")
                .child("\(uploadID.uuidString).png")
                .delete { _ in }
        }
        pickedImages.remove(at: index)
    }

    func livePetUnitPhoto(for unitID: String) -> UIImage? {
        livePetUnitPhotos[unitID]?.image
    }

    var firstLivePetPhoto: UIImage? {
        if let first = pickedImages.first {
            return first
        }
        for unit in livePetUnits {
            if let photo = livePetUnitPhotos[unit.id]?.image {
                return photo
            }
        }
        return nil
    }

    var firstLivePetUnitPhotoURL: String? {
        for unit in livePetUnits {
            if let draft = livePetUnitPhotos[unit.id],
               let url = draft.uploadedURL,
               !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return url
            }
        }
        return nil
    }

    /// Replaces only this draft animal's local identity photo. Upload is deferred
    /// until the complete intake validates, so browsing or discarding a draft
    /// never creates Storage objects.
    func setLivePetUnitPhoto(_ image: UIImage, unitID: String) -> String? {
        guard !isEditingLivePet,
              livePetUnits.contains(where: { $0.id == unitID }) else { return nil }
        guard canManageStock else {
            return Language.get(
                "LivePetIntake_UnitPhotoPermissionRequired",
                alter: "تحتاج إلى صلاحية إدارة المخزون لإرفاق صورة الحيوان."
            )
        }
        guard var prepared = Self.prepareLivePetUnitPhoto(image) else {
            return Language.get(
                "LivePetIntake_UnitPhotoPrepareFailed",
                alter: "تعذر تجهيز هذه الصورة. اختر صورة أخرى وحاول مجدداً."
            )
        }

        // Selecting the same image again must retain the immutable staged object
        // instead of attempting a forbidden Storage overwrite.
        if let current = livePetUnitPhotos[unitID],
           current.contentSHA256 == prepared.contentSHA256 {
            prepared.objectWasUploaded = current.objectWasUploaded
            prepared.uploadedURL = current.uploadedURL
        }
        livePetUnitPhotos[unitID] = prepared
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return nil
    }

    func removeLivePetUnitPhoto(unitID: String) {
        guard livePetUnitPhotos.removeValue(forKey: unitID) != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private static func prepareLivePetUnitPhoto(_ source: UIImage) -> PPLivePetUnitPhotoDraft? {
        PPLivePetUnitPhotoStorageService.prepareLivePetUnitPhoto(source)
    }

    private func uploadLivePetUnitPhotosIfNeeded() async throws -> [String: [String]] {
        guard editingAccessory == nil, liveInventoryMode == .individual else { return [:] }
        let currentUnits = livePetUnits.filter { livePetUnitPhotos[$0.id] != nil }
        guard !currentUnits.isEmpty else { return [:] }
        guard canManageStock else {
            throw livePetUnitPhotoError(
                code: 1,
                key: "LivePetIntake_UnitPhotoPermissionRequired",
                fallback: "تحتاج إلى صلاحية إدارة المخزون لإرفاق صورة الحيوان."
            )
        }
        guard let actorUID = Auth.auth().currentUser?.uid, !actorUID.isEmpty else {
            throw livePetUnitPhotoError(
                code: 2,
                key: "LivePetIntake_UnitPhotoSessionExpired",
                fallback: "انتهت جلسة الموظف. سجّل الدخول مجدداً قبل رفع صورة الحيوان."
            )
        }

        var mediaByUnitID: [String: [String]] = [:]
        for (position, unit) in currentUnits.enumerated() {
            guard var photo = livePetUnitPhotos[unit.id] else { continue }
            if let uploadedURL = photo.uploadedURL, !uploadedURL.isEmpty {
                mediaByUnitID[unit.id] = [uploadedURL]
                continue
            }

            let objectName = "\(photo.contentSHA256)_identity.jpg"
            let reference = Storage.storage().reference()
                .child("live-pet-units")
                .child(actorUID)
                .child(liveCreateCommandID)
                .child(unit.id)
                .child(objectName)
            let expectedMetadata: [String: String] = [
                "uploaded_by": actorUID,
                "media_type": "image",
                "media_scope": "live_pet_unit_internal",
                "command_id": liveCreateCommandID,
                "draft_unit_id": unit.id,
                "content_sha256": photo.contentSHA256,
            ]

            if let existingMetadata = try await livePetUnitPhotoMetadata(for: reference) {
                guard existingMetadata.contentType == "image/jpeg",
                      existingMetadata.size == Int64(photo.encodedData.count),
                      expectedMetadata.allSatisfy({ existingMetadata.customMetadata[$0.key] == $0.value }) else {
                    throw livePetUnitPhotoError(
                        code: 3,
                        key: "LivePetIntake_UnitPhotoStagedConflict",
                        fallback: "تعارضت الصورة المجهزة مع ملف موجود. اختر الصورة مجدداً وحاول مرة أخرى."
                    )
                }
                photo.objectWasUploaded = true
            } else {
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                metadata.customMetadata = expectedMetadata
                try await putLivePetUnitPhoto(photo.encodedData, metadata: metadata, at: reference)
                photo.objectWasUploaded = true
            }

            let downloadURL = try await livePetUnitPhotoDownloadURL(for: reference)
            photo.uploadedURL = downloadURL.absoluteString
            livePetUnitPhotos[unit.id] = photo
            mediaByUnitID[unit.id] = [downloadURL.absoluteString]
            submitProgress = Double(position + 1) / Double(currentUnits.count)
        }
        return mediaByUnitID
    }

    private func livePetUnitPhotoMetadata(
        for reference: StorageReference
    ) async throws -> PPLivePetUnitPhotoMetadataSnapshot? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                reference.getMetadata { metadata, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let metadata {
                        continuation.resume(returning: PPLivePetUnitPhotoMetadataSnapshot(
                            contentType: metadata.contentType,
                            size: metadata.size,
                            customMetadata: metadata.customMetadata ?? [:]
                        ))
                    } else {
                        continuation.resume(throwing: self.livePetUnitPhotoError(
                            code: 4,
                            key: "LivePetIntake_UnitPhotoUploadFailed",
                            fallback: "تعذر التحقق من صورة الحيوان المرفوعة. حاول مرة أخرى."
                        ))
                    }
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain,
               nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return nil
            }
            throw error
        }
    }

    private func putLivePetUnitPhoto(
        _ data: Data,
        metadata: StorageMetadata,
        at reference: StorageReference
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func livePetUnitPhotoDownloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: self.livePetUnitPhotoError(
                        code: 5,
                        key: "LivePetIntake_UnitPhotoUploadFailed",
                        fallback: "تعذر إكمال رفع صورة الحيوان. حاول مرة أخرى."
                    ))
                }
            }
        }
    }

    private func livePetUnitPhotoError(code: Int, key: String, fallback: String) -> NSError {
        NSError(
            domain: "PPAdmin.LivePetUnitPhoto",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: Language.get(key, alter: fallback)]
        )
    }

    private func updateUnsavedChanges() {
        guard initialSetupComplete else {
            guard !isPopulatingInitialValues, !isApplyingCategoryHydration else { return }
            hasUnsavedChanges = true
            errorMessage = nil
            submissionFailureKind = nil
            return
        }
        hasUnsavedChanges = true
        errorMessage = nil
        submissionFailureKind = nil
        if !isSubmitting && !isLivePet {
            standardSaveCommandID = nil
        }
    }

    // MARK: - Validation

    func validate() -> (isValid: Bool, message: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || basePrice <= 0 {
            return (false, Language.get("Name and price are required.", alter: "يرجى إدخال اسم وسعر المنتج بدقة."))
        }
        if !isLivePet {
            if hasNoCategorySelected {
                return (false, Language.get("Please select pet species.", alter: "يرجى اختيار النوع والفئة الرئيسية للحيوان."))
            }
            let (groupsValid, groupError) = validateQuantityGroups()
            if !groupsValid {
                return (false, groupError)
            }
        } else {
            if selectedMainKind == nil {
                return (false, Language.get("Please select pet species.", alter: "يرجى اختيار النوع والفئة الرئيسية للحيوان."))
            }
        }
        if physicalSpecMode == .dimensions && !isValidDimensionsInput() {
            return (false, Language.get(
                "CatalogIntake_ValidationDimensions",
                alter: "أدخل أبعاداً صالحة (العرض والارتفاع) وبحد أقصى منزلتين عشريتين."
            ))
        }
        if (physicalSpecMode == .weightVolume || !weightText.isEmpty) && !isValidWeightInput() {
            return (false, Language.get(
                "CatalogIntake_ValidationWeight",
                alter: "أدخل وزناً أو حجماً صالحاً وبحد أقصى ثلاث منازل عشرية."
            ))
        }
        if !isLivePet {
            let normalizedCost = costPriceText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedCost.isEmpty {
                guard let value = Double(normalizedCost), value >= 0, value <= 999_999_999.99,
                      abs(value * 100 - (value * 100).rounded()) < 0.000_001 else {
                    return (false, Language.get(
                        "CatalogIntake_ValidationCost",
                        alter: "أدخل تكلفة استلام صالحة وبحد أقصى منزلتين عشريتين."
                    ))
                }
            } else if editingAccessory == nil, quantity > 0, canViewStockCosts {
                return (false, Language.get(
                    "CatalogIntake_CostRequiredForOpeningStock",
                    alter: "أدخل تكلفة الاستلام للمخزون الافتتاحي، أو أنشئ الصنف بكمية صفر."
                ))
            }
        }
        if (!isLivePet || liveInventoryMode == .quantity) && !isValidDiscountPercentInput() {
            let key = isLivePet ? "LivePetIntake_ValidationDiscountPercent" : "CatalogIntake_ValidationDiscountPercent"
            return (false, Language.get(key, alter: "أدخل نسبة خصم بين 0 و100 وبحد أقصى منزلتين عشريتين."))
        }
        if (!isLivePet || liveInventoryMode == .quantity) && !isValidDiscountAmountInput() {
            let key = isLivePet ? "LivePetIntake_ValidationDiscountAmount" : "CatalogIntake_ValidationDiscountAmount"
            return (false, Language.get(key, alter: "أدخل مبلغ خصم صالحاً وبحد أقصى منزلتين عشريتين."))
        }
        if isLivePet {
            if trimmedName.utf16.count > 90 {
                return (false, Language.get("LivePetIntake_ValidationNameLength", alter: "يجب ألا يتجاوز الاسم 90 حرفاً."))
            }
            if !trimmedNameEn.isEmpty && trimmedNameEn.utf16.count > 90 {
                return (false, Language.get("LivePetIntake_ValidationNameLengthEn", alter: "يجب ألا يتجاوز الاسم بالإنجليزية 90 حرفاً."))
            }
            if desc.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 4_000 {
                return (false, Language.get("LivePetIntake_ValidationDescriptionLength", alter: "يجب ألا يتجاوز الوصف 4000 حرف."))
            }
            let trimmedDescEn = descEn.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDescEn.isEmpty && trimmedDescEn.utf16.count > 4_000 {
                return (false, Language.get("LivePetIntake_ValidationDescriptionLengthEn", alter: "يجب ألا يتجاوز الوصف بالإنجليزية 4000 حرف."))
            }
            if liveInventoryMode == .quantity {
                if liveSupplier.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 100 {
                    return (false, Language.get("LivePetIntake_ValidationSupplierLength", alter: "يجب ألا يتجاوز اسم المورد 100 حرف."))
                }
                if liveIntakeNotes.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 {
                    return (false, Language.get("LivePetIntake_ValidationNotesLength", alter: "يجب ألا تتجاوز ملاحظات الاستلام 500 حرف."))
                }
            }
            if liveInventoryMode == .quantity, quantity < 1 {
                return (false, Language.get("LivePet_Validation_GroupQuantity", alter: "أدخل كمية صحيحة لا تقل عن حيوان واحد للمجموعة."))
            }
            if liveInventoryMode == .individual && editingAccessory == nil {
                guard !livePetUnits.isEmpty else {
                    return (false, Language.get("LivePet_Validation_UnitRequired", alter: "أضف سجلاً واحداً على الأقل لحيوان محدد."))
                }
                if livePetUnits.contains(where: {
                    $0.supplier.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 100
                }) {
                    return (false, Language.get("LivePetIntake_ValidationSupplierLength", alter: "يجب ألا يتجاوز اسم المورد 100 حرف."))
                }
                if livePetUnits.contains(where: {
                    $0.notes.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500
                }) {
                    return (false, Language.get("LivePetIntake_ValidationNotesLength", alter: "يجب ألا تتجاوز ملاحظات الاستلام 500 حرف."))
                }
                let normalizedRings = livePetUnits.map {
                    $0.ringTag.precomposedStringWithCompatibilityMapping
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .lowercased(with: Locale(identifier: "en_US_POSIX"))
                }
                if normalizedRings.contains(where: { $0.isEmpty || $0.utf16.count > 80 }) {
                    return (false, Language.get("LivePet_Validation_RingRequired", alter: "أدخل رقم حلقة أو شريحة صالحاً لكل حيوان."))
                }
                if Set(normalizedRings).count != normalizedRings.count {
                    return (false, Language.get("LivePet_Validation_RingDuplicate", alter: "لا يمكن تكرار رقم الحلقة أو الشريحة داخل نفس الإدخال."))
                }
                let pricesAreValid = livePetUnits.allSatisfy { unit in
                    let clean = unit.sellingPriceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let value = Double(clean), value > 0, value <= 999_999_999.99 else { return false }
                    return abs(value * 100 - (value * 100).rounded()) < 0.000_001
                }
                if !pricesAreValid {
                    return (false, Language.get("LivePet_Validation_UnitPrice", alter: "حدد سعر بيع صالحاً لكل حيوان وبحد أقصى منزلتين عشريتين."))
                }
                if canViewStockCosts {
                    let costsAreValid = livePetUnits.allSatisfy { unit in
                        let clean = unit.purchaseCostText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let value = Double(clean), value >= 0, value <= 999_999_999.99 else { return false }
                        return abs(value * 100 - (value * 100).rounded()) < 0.000_001
                    }
                    if !costsAreValid {
                        return (false, Language.get("LivePet_Validation_UnitCost", alter: "أدخل تكلفة استلام صالحة لكل حيوان وبحد أقصى منزلتين عشريتين."))
                    }
                }
            }
            if liveInventoryMode == .quantity && canViewStockCosts {
                let clean = liveGroupCostText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(clean), value >= 0, value <= 999_999_999.99,
                      abs(value * 100 - (value * 100).rounded()) < 0.000_001 else {
                    return (false, Language.get("LivePet_Validation_UnitCost", alter: "أدخل تكلفة استلام صالحة وبحد أقصى منزلتين عشريتين."))
                }
            }
        }
        if editingAccessory == nil {
            let requestedOpeningQuantity = isLivePet && liveInventoryMode == .individual
                ? livePetUnits.count
                : quantity
            if requestedOpeningQuantity > 0 {
                let activeBranchID = BranchContextStore.shared.activeBranch?.branchID
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let selectedBranchID = selectedStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedBranchID = (!selectedBranchID.isEmpty && selectedBranchID != "main_store")
                    ? selectedBranchID
                    : activeBranchID
                if resolvedBranchID.isEmpty || resolvedBranchID == "main_store" {
                    return (false, Language.get(
                        "Inventory_SpecificBranchRequired",
                        alter: "اختر فرعاً محدداً قبل إنشاء مخزون أولي لهذا الصنف."
                    ))
                }
            }
        }
        return (true, nil)
    }

    // MARK: - Save Mutation Flow

    func saveAccessory() {
        guard !isSubmitting, !hasCompletedSave else { return }

        if isLivePet, let recovery = livePetRecovery {
            isSubmitting = true
            errorMessage = nil
            saveSuccessMessage = nil
            submissionFailureKind = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor [weak self] in
                await self?.executeLivePetRecovery(recovery)
            }
            return
        }
        
        let (isValid, validationMessage) = validate()
        guard isValid else {
            errorMessage = validationMessage
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSubmitting = true
        errorMessage = nil
        saveSuccessMessage = nil
        submissionFailureKind = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let accessory = editingAccessory.map { PetAccessory.deepCopy(from: $0) } ?? PetAccessory()
        accessory.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.descEn = descEn.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.sku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCost = costPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedCost.isEmpty, let costVal = decimalValue(normalizedCost) {
            accessory.costPrice = NSNumber(value: costVal)
        } else {
            accessory.costPrice = nil
        }
        accessory.price = NSNumber(value: basePrice)
        accessory.discountPercent = discountPercent > 0 ? NSNumber(value: discountPercent) : nil
        accessory.discountAmount = discountAmount > 0 ? NSNumber(value: discountAmount) : nil
        accessory.hasOffer = discountPercent > 0 || discountAmount > 0
        if wholesaleEnabled {
            let wpVal: Double = {
                if let defaultW = quantityGroups.first(where: { $0.defaultForWholesale && $0.wholesaleEnabled }) ?? quantityGroups.first(where: { $0.wholesaleEnabled }), defaultW.wholesalePrice > 0 {
                    return defaultW.wholesalePrice
                }
                return decimalValue(wholesalePriceText) ?? 0.0
            }()
            accessory.wholesalePrice = wpVal > 0 ? NSNumber(value: wpVal) : nil
        } else {
            accessory.wholesalePrice = nil
        }
        accessory.hasCommerceConfig = true
        accessory.quantity = max(0, quantity)
        accessory.noStock = (quantity <= 0)
        
        accessory.condition = (isFood || condition == .new) ? .new : .used
        accessory.isNew = (accessory.condition != .used)
        accessory.accessKindType = selectedKind
        
        if isLivePet {
            accessory.petMainCategoryID = selectedMainKind?.id ?? 0
            accessory.petSubCategoryID = selectedSubKind?.id ?? 0
            accessory.isAllCategories = false
            accessory.isAllSubCategories = false
            accessory.petMainCategoryIDs = nil
            accessory.petSubCategoryIDs = nil
        } else {
            accessory.isAllCategories = isAllCategoriesSelected
            accessory.isAllSubCategories = isAllSubCategoriesSelected
            accessory.petMainCategoryIDs = isAllCategoriesSelected ? [] : Array(selectedMainKinds).map { NSNumber(value: $0) }
            accessory.petSubCategoryIDs = isAllSubCategoriesSelected ? [] : Array(selectedSubKinds).map { NSNumber(value: $0) }
            accessory.petMainCategoryID = isAllCategoriesSelected ? 0 : (selectedMainKind?.id ?? selectedMainKinds.first ?? 0)
            accessory.petSubCategoryID = isAllSubCategoriesSelected ? 0 : (selectedSubKind?.id ?? selectedSubKinds.first ?? 0)
        }
        
        let defaultActiveBranch = BranchContextStore.shared.activeBranch?.branchID ?? "main_store"
        let branchIdToSave = (selectedStoreID.isEmpty || selectedStoreID == "main_store") && defaultActiveBranch != "main_store"
            ? defaultActiveBranch
            : (selectedStoreID.isEmpty ? "main_store" : selectedStoreID)
        accessory.storeID = branchIdToSave
        accessory.branchID = branchIdToSave
        if let b = BranchContextStore.shared.branch(for: branchIdToSave) {
            accessory.branchCode = b.code
            accessory.storeName = b.localizedName()
        } else {
            accessory.storeName = selectedStoreName.isEmpty ? Language.get("Main Store", alter: "المتجر الرئيسي") : selectedStoreName
        }

        switch physicalSpecMode {
        case .dimensions:
            accessory.weight = nil
            accessory.weightUnit = nil
            accessory.weightText = nil

            let cleanW = dimensionWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanH = dimensionHeightText.trimmingCharacters(in: .whitespacesAndNewlines)
            let valW = decimalValue(cleanW)
            let valH = decimalValue(cleanH)

            if let w = valW, let h = valH, w > 0 || h > 0 {
                let canonicalW = canonicalDecimalText(w, maximumFractionDigits: 2)
                let canonicalH = canonicalDecimalText(h, maximumFractionDigits: 2)
                accessory.dimensionWidth = NSNumber(value: w)
                accessory.dimensionHeight = NSNumber(value: h)
                accessory.dimensionUnit = dimensionUnit
                accessory.size = "\(canonicalW) × \(canonicalH) \(dimensionUnit)"
            } else if let w = valW, w > 0 {
                let canonicalW = canonicalDecimalText(w, maximumFractionDigits: 2)
                accessory.dimensionWidth = NSNumber(value: w)
                accessory.dimensionHeight = nil
                accessory.dimensionUnit = dimensionUnit
                accessory.size = "\(canonicalW) \(dimensionUnit)"
            } else if let h = valH, h > 0 {
                let canonicalH = canonicalDecimalText(h, maximumFractionDigits: 2)
                accessory.dimensionWidth = nil
                accessory.dimensionHeight = NSNumber(value: h)
                accessory.dimensionUnit = dimensionUnit
                accessory.size = "\(canonicalH) \(dimensionUnit)"
            } else {
                accessory.dimensionWidth = nil
                accessory.dimensionHeight = nil
                accessory.dimensionUnit = nil
                accessory.size = nil
            }

        case .standardSize:
            accessory.dimensionWidth = nil
            accessory.dimensionHeight = nil
            accessory.dimensionUnit = nil
            accessory.weight = nil
            accessory.weightUnit = nil
            accessory.weightText = nil
            let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
            accessory.size = trimmedSize.isEmpty ? nil : trimmedSize

        case .weightVolume:
            accessory.dimensionWidth = nil
            accessory.dimensionHeight = nil
            accessory.dimensionUnit = nil
            accessory.size = nil
            let normalizedWeight = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedWeight.isEmpty {
                accessory.weight = nil
                accessory.weightUnit = nil
                accessory.weightText = nil
            } else if let weightValue = decimalValue(normalizedWeight) {
                let canonicalWeight = canonicalDecimalText(weightValue, maximumFractionDigits: 3)
                accessory.weight = NSNumber(value: weightValue)
                accessory.weightUnit = weightUnit
                accessory.weightText = "\(canonicalWeight) \(weightUnit)"
            }

        case .none:
            accessory.dimensionWidth = nil
            accessory.dimensionHeight = nil
            accessory.dimensionUnit = nil
            accessory.size = nil
            accessory.weight = nil
            accessory.weightUnit = nil
            accessory.weightText = nil
        }
        
        accessory.expiryDate = (isFood && hasExpiryDate) ? expiryDate : nil
        accessory.active = !isDraft
        
        if accessory.createdAt == nil {
            accessory.createdAt = Date()
        }
        if accessory.ownerID.isEmpty {
            accessory.ownerID = Auth.auth().currentUser?.uid ?? ""
        }
        
        accessory.normalizeInventoryState()

        let oldImageURLs = editingAccessory?.imageURLsArray ?? []
        let currentExistingURLs = existingImageURLs
        let currentExistingMetadata = alignedImageMetadata(
            urls: currentExistingURLs,
            metadata: existingImageMetadata
        )

        // Upload newly picked images
        if pickedImages.isEmpty {
            accessory.imageURLsArray = currentExistingURLs
            accessory.imageMeta = currentExistingMetadata
            pendingSavedAccessoryDraft = accessory
            finalizeAccessorySave(accessory: accessory, oldImageURLs: oldImageURLs)
        } else {
            let uploadIDs = pickedImageUploadIDs
            uploadNewImages(images: pickedImages, uploadIDs: uploadIDs) { [weak self] uploadedURLs, metaArray, uploadError in
                guard let self = self else { return }
                if let err = uploadError {
                    self.isSubmitting = false
                    self.errorMessage = err.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                let uploadedURLs = uploadedURLs ?? []
                let uploadedMetadata = metaArray ?? []
                let finalURLs = currentExistingURLs + uploadedURLs
                let finalMetadata = currentExistingMetadata + uploadedMetadata
                for (url, uploadID) in zip(uploadedURLs, uploadIDs) {
                    self.pendingUnsavedUploads[url] = uploadID
                }
                // Promote uploaded media into retained state before the mutation.
                // A failed catalog save can retry the same uploads without leaks
                // or reordering the primary image and its metadata.
                self.existingImageURLs = finalURLs
                self.existingImageMetadata = finalMetadata
                self.pickedImages.removeAll()
                self.pickedImageUploadIDs.removeAll()
                accessory.imageURLsArray = finalURLs
                accessory.imageMeta = finalMetadata
                self.pendingSavedAccessoryDraft = accessory
                self.finalizeAccessorySave(accessory: accessory, oldImageURLs: oldImageURLs)
            }
        }
    }

    private func uploadNewImages(
        images: [UIImage],
        uploadIDs: [UUID],
        completion: @escaping ([String]?, [[AnyHashable: Any]]?, Error?) -> Void
    ) {
        guard uploadIDs.count == images.count else {
            completion(
                nil,
                nil,
                NSError(
                    domain: "PPAccessoryEditorImageUpload",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "CatalogIntake_PhotoUploadFailed",
                        alter: "تعذر إكمال رفع الصور. حاول مرة أخرى."
                    )]
                )
            )
            return
        }
        let encodedImages: [(image: UIImage, data: Data)] = images.compactMap { image in
            guard let data = image.pngData() else { return nil }
            return (image, data)
        }
        guard encodedImages.count == images.count else {
            completion(
                nil,
                nil,
                NSError(
                    domain: "PPAccessoryEditorImageUpload",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: Language.get(
                            "CatalogIntake_PhotoEncodingFailed",
                            alter: "تعذر تجهيز إحدى الصور للرفع. أعد اختيار الصورة وحاول مرة أخرى."
                        )
                    ]
                )
            )
            return
        }

        let storageRef = Storage.storage().reference()
        let group = DispatchGroup()
        var uploadedURLs = Array<String?>(repeating: nil, count: encodedImages.count)
        var metaArray = Array<[AnyHashable: Any]?>(repeating: nil, count: encodedImages.count)
        var firstError: Error?
        let lock = NSLock()

        for (index, encodedImage) in encodedImages.enumerated() {
            group.enter()
            let image = encodedImage.image
            let imgRef = storageRef.child("petAccessories").child("\(uploadIDs[index].uuidString).png")
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/png"
            metadata.customMetadata = [
                "uploaded_by": Auth.auth().currentUser?.uid ?? "",
                "entity_type": "accessory",
                "media_type": "image"
            ]

            imgRef.putData(encodedImage.data, metadata: metadata) { _, error in
                if let err = error {
                    lock.lock()
                    if firstError == nil { firstError = err }
                    lock.unlock()
                    group.leave()
                    return
                }

                imgRef.downloadURL { url, downloadError in
                    lock.lock()
                    if let urlString = url?.absoluteString {
                        uploadedURLs[index] = urlString
                        metaArray[index] = [
                            "url": urlString,
                            "width": Double(image.size.width),
                            "height": Double(image.size.height)
                        ]
                    } else if firstError == nil {
                        firstError = downloadError ?? NSError(
                            domain: "PPAccessoryEditorImageUpload",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: Language.get(
                                "CatalogIntake_PhotoUploadFailed",
                                alter: "تعذر إكمال رفع الصور. حاول مرة أخرى."
                            )]
                        )
                    }
                    lock.unlock()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let uploadError = firstError
            let completedURLs = uploadedURLs
            let completedMetadata = metaArray
            lock.unlock()

            if let uploadError {
                // Keep stable per-selection object paths and the selected images.
                // A retry overwrites/reuses these paths, so partial uploads never
                // accumulate UUID-addressed orphan blobs across attempts.
                completion(nil, nil, uploadError)
            } else {
                completion(completedURLs.compactMap { $0 }, completedMetadata.compactMap { $0 }, nil)
            }
        }
    }

    private func buildCommercePayload() -> [String: Any]? {
        guard !isIndividualLivePet else { return nil }
        ensureDefaultSingleGroup()
        guard !quantityGroups.isEmpty else { return nil }

        let groupsPayload: [[String: Any]] = quantityGroups.map { g in
            var dict: [String: Any] = [
                "id": g.id,
                "nameAr": g.nameAr.isEmpty ? (Language.isRTL() ? "وحدة" : "Unit") : g.nameAr,
                "nameEn": g.nameEn.isEmpty ? "Unit" : g.nameEn,
                "unitsPerGroup": max(1, g.unitsPerGroup),
                "barcode": g.barcode.isEmpty ? NSNull() : g.barcode,
                "sku": g.sku.isEmpty ? NSNull() : g.sku,
                "sortOrder": g.sortOrder,
                "retailEnabled": g.retailEnabled,
                "wholesaleEnabled": g.wholesaleEnabled,
                "retailPriceMinor": g.retailPriceMinor,
                "wholesalePriceMinor": g.wholesaleEnabled ? (g.wholesalePriceMinor as Any) : NSNull(),
                "defaultForRetail": g.defaultForRetail,
                "defaultForWholesale": g.defaultForWholesale,
                "active": g.active
            ]
            return dict
        }

        return [
            "currency": "QAR",
            "baseUnit": [
                "id": commerceBaseUnitID,
                "nameAr": commerceBaseUnitNameAr,
                "nameEn": commerceBaseUnitNameEn
            ],
            "quantityGroups": groupsPayload
        ]
    }

    private func finalizeAccessorySave(accessory: PetAccessory, oldImageURLs: [String]) {
        if isLivePet {
            Task { @MainActor [weak self] in
                await self?.finalizeLivePetSave(accessory: accessory, oldImageURLs: oldImageURLs)
            }
            return
        }

        let resolvedBranchId: String = {
            if let bid = accessory.branchID, !bid.isEmpty, bid != "main_store" {
                if let matched = PPBranchContextManager.shared().branch(withID: bid) {
                    return matched.branchID
                }
                return bid
            }
            if let activeId = BranchContextStore.shared.activeBranch?.branchID, !activeId.isEmpty, activeId != "main_store" {
                return activeId
            }
            return accessory.branchID ?? ""
        }()

        let commercePayload = buildCommercePayload()
        let commandID: String = {
            if let existing = standardSaveCommandID, !existing.isEmpty {
                return existing
            }
            let action = accessory.accessoryID.isEmpty ? "create" : "update"
            let generated = PPInventoryCommandService.shared.generateCommandId(
                action: action,
                targetId: accessory.accessoryID.isEmpty ? "new" : accessory.accessoryID
            )
            standardSaveCommandID = generated
            return generated
        }()

        PPInventoryCommandService.shared.saveProduct(
            accessory: accessory,
            branchId: resolvedBranchId,
            commerce: commercePayload,
            expectedRevision: accessory.revision > 0 ? accessory.revision : nil,
            commandId: commandID
        ) { [weak self] cmdResult, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let err = error {
                    self.isSubmitting = false
                    self.errorMessage = err.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                guard let result = cmdResult,
                      let productID = result.productId,
                      !productID.isEmpty else {
                    self.isSubmitting = false
                    self.errorMessage = Language.get(
                        "Inventory_InvalidCommandResponse",
                        alter: "تعذر التحقق من استجابة خدمة المخزون."
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                PPInventoryCommandService.shared.readBackProduct(
                    productId: productID,
                    minimumRevision: result.revision
                ) { [weak self] authoritativeAccessory, readbackError in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let readbackError {
                            self.isSubmitting = false
                            self.errorMessage = String(
                                format: Language.get(
                                    "Inventory_CommandAcceptedReadbackPending_Format",
                                    alter: "اعتمد الخادم الحفظ، لكن تعذر تأكيد النسخة النهائية. أعد المحاولة دون تعديل البيانات. التفاصيل: %@"
                                ),
                                readbackError.localizedDescription
                            )
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            return
                        }
                        guard let confirmed = authoritativeAccessory else {
                            self.isSubmitting = false
                            self.errorMessage = Language.get(
                                "Inventory_ReadbackMissing",
                                alter: "اعتمد الخادم العملية، لكن تعذر العثور على الصنف عند التحقق النهائي. أعد المحاولة دون تغيير البيانات."
                            )
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            return
                        }

                        accessory.accessoryID = confirmed.accessoryID
                        accessory.revision = confirmed.revision
                        self.commitSavedAccessory(confirmed)
                        self.standardSaveCommandID = nil

                        // Media cleanup is safe only after authoritative readback
                        // proves which URLs the committed catalog retained.
                        let retainedURLs = Set(confirmed.imageURLsArray ?? [])
                        for oldURL in oldImageURLs where !oldURL.isEmpty && !retainedURLs.contains(oldURL) {
                            if let ref = try? Storage.storage().reference(forURL: oldURL) {
                                ref.delete { _ in }
                            }
                        }

                        let message = (self.editingAccessory != nil)
                            ? Language.get("Your changes were saved successfully.", alter: "تم حفظ التعديلات بنجاح")
                            : Language.get("Accessory has been created.", alter: "تمت إضافة الصنف بنجاح")
                        self.completeSuccessfulSave(message: message)
                    }
                }
            }
        }
    }

    private func commitSavedAccessory(_ saved: PetAccessory) {
        guard let original = editingAccessory else { return }
        original.accessoryID = saved.accessoryID
        original.name = saved.name
        original.nameEn = saved.nameEn
        original.desc = saved.desc
        original.descEn = saved.descEn
        original.sku = saved.sku
        original.barcode = saved.barcode
        original.costPrice = saved.costPrice
        original.price = saved.price
        original.wholesalePrice = saved.wholesalePrice
        original.hasCommerceConfig = saved.hasCommerceConfig
        original.discountPercent = saved.discountPercent
        original.discountAmount = saved.discountAmount
        original.weightText = saved.weightText
        original.weight = saved.weight
        original.weightUnit = saved.weightUnit
        original.size = saved.size
        original.dimensionWidth = saved.dimensionWidth
        original.dimensionHeight = saved.dimensionHeight
        original.dimensionUnit = saved.dimensionUnit
        original.imageURLsArray = saved.imageURLsArray
        original.imageMeta = saved.imageMeta
        original.petMainCategoryID = saved.petMainCategoryID
        original.petSubCategoryID = saved.petSubCategoryID
        original.condition = saved.condition
        original.accessKindType = saved.accessKindType
        original.expiryDate = saved.expiryDate
        original.ownerID = saved.ownerID
        original.createdAt = saved.createdAt
        original.storeID = saved.storeID
        original.storeName = saved.storeName
        original.branchID = saved.branchID
        original.branchCode = saved.branchCode
        original.quantity = saved.quantity
        original.noStock = saved.noStock
        original.active = saved.active
        original.isNew = saved.isNew
        original.hasOffer = saved.hasOffer
        original.showInAppMarket = saved.showInAppMarket
        original.relatedAccessories = saved.relatedAccessories
        original.revision = saved.revision
    }

    private func commitConfirmedLivePetForm(retainedURLs: [String]) {
        guard let original = editingAccessory else { return }
        original.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        original.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        original.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        original.descEn = descEn.trimmingCharacters(in: .whitespacesAndNewlines)
        original.price = NSNumber(value: basePrice)
        original.discountPercent = liveInventoryMode == .quantity && discountPercent > 0
            ? NSNumber(value: discountPercent)
            : nil
        original.discountAmount = liveInventoryMode == .quantity && discountAmount > 0
            ? NSNumber(value: discountAmount)
            : nil
        original.hasOffer = original.discountPercent != nil || original.discountAmount != nil
        original.quantity = liveInventoryMode == .individual ? livePetUnits.count : max(0, quantity)
        original.noStock = original.quantity <= 0
        original.condition = .new
        original.isNew = true
        original.accessKindType = .typeLivePets
        original.petMainCategoryID = selectedMainKind?.id ?? 0
        original.petSubCategoryID = selectedSubKind?.id ?? 0
        let defaultActiveBranch = BranchContextStore.shared.activeBranch?.branchID ?? "main_store"
        let liveBranchId = (selectedStoreID.isEmpty || selectedStoreID == "main_store") && defaultActiveBranch != "main_store"
            ? defaultActiveBranch
            : (selectedStoreID.isEmpty ? "main_store" : selectedStoreID)
        original.storeID = liveBranchId
        original.branchID = liveBranchId
        if let b = BranchContextStore.shared.branch(for: liveBranchId) {
            original.branchCode = b.code
            original.storeName = b.localizedName()
        } else {
            original.storeName = selectedStoreName
        }
        original.inventoryMode = liveInventoryMode.rawValue
        if liveInventoryMode == .individual {
            original.standardSellingPrice = NSNumber(value: basePrice)
        }
        original.imageURLsArray = retainedURLs
        original.active = !isDraft
        original.normalizeInventoryState()
    }

    private func completeSuccessfulSave(message: String) {
        guard !hasCompletedSave else { return }
        isSubmitting = false
        livePetUnitPhotos.removeAll()
        hasUnsavedChanges = false
        submissionFailureKind = nil
        pendingUnsavedUploads.removeAll()
        pickedImageUploadIDs.removeAll()
        pendingSavedAccessoryDraft = nil
        saveSuccessMessage = message
        hasCompletedSave = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        guard !didScheduleSuccessfulDismissal else { return }
        didScheduleSuccessfulDismissal = true
        let dismissalDelay = UIAccessibility.isVoiceOverRunning ? 3.5 : 1.1
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissalDelay) { [weak self] in
            guard let self, self.hasCompletedSave else { return }
            self.onDismiss()
        }
    }

    private func finalizeLivePetSave(accessory: PetAccessory, oldImageURLs: [String]) async {
        let unitMediaURLsByID: [String: [String]]
        do {
            unitMediaURLsByID = try await uploadLivePetUnitPhotosIfNeeded()
        } catch {
            isSubmitting = false
            submitProgress = 0
            let nsError = error as NSError
            let permissionFailure = (nsError.domain == StorageErrorDomain
                && [StorageErrorCode.unauthenticated.rawValue, StorageErrorCode.unauthorized.rawValue].contains(nsError.code))
                || (nsError.domain == "PPAdmin.LivePetUnitPhoto" && [1, 2].contains(nsError.code))
            submissionFailureKind = permissionFailure ? .denied : .retryable
            errorMessage = String(
                format: Language.get(
                    "LivePetIntake_UnitPhotoUploadFailureFormat",
                    alter: "تعذر إكمال صورة الحيوان. لم يتم إنشاء المخزون. التفاصيل: %@"
                ),
                error.localizedDescription
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        submitProgress = 0

        let allUnitURLs = unitMediaURLsByID.values.flatMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var resolvedImageURLs = (accessory.imageURLsArray ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if resolvedImageURLs.isEmpty && !allUnitURLs.isEmpty {
            resolvedImageURLs = allUnitURLs
            accessory.imageURLsArray = resolvedImageURLs
            if existingImageURLs.isEmpty {
                existingImageURLs = resolvedImageURLs
            }
        }
        pendingSavedAccessoryDraft = accessory

        let productID = editingAccessory?.accessoryID ?? ""
        var catalogValues: [String: Any] = [
            "name": accessory.name ?? "",
            "nameEn": accessory.nameEn ?? "",
            "desc": accessory.desc ?? "",
            "descEn": accessory.descEn ?? "",
            "petMainCategoryID": accessory.petMainCategoryID,
            "petSubCategoryID": accessory.petSubCategoryID,
            "category": "Live Pets",
            "imageURLsArray": resolvedImageURLs,
            "active": accessory.active,
            "showInAppMarket": !isDraft,
            "isNew": true,
        ]
        if liveInventoryMode == .quantity {
            catalogValues["price"] = basePrice
            catalogValues["discountPercent"] = accessory.discountPercent ?? NSNull()
            catalogValues["discountAmount"] = accessory.discountAmount ?? NSNull()
            catalogValues["hasOffer"] = accessory.hasOffer
            if let wp = accessory.wholesalePrice, wp.doubleValue > 0 {
                catalogValues["wholesalePrice"] = wp
            }
            catalogValues["hasCommerceConfig"] = true
        }

        let unitPayloads: [[String: Any]] = livePetUnits.map { unit in
            let sellingPrice = Double(unit.sellingPriceText.replacingOccurrences(of: ",", with: ".")) ?? basePrice
            let purchaseCost = Double(unit.purchaseCostText.replacingOccurrences(of: ",", with: "."))
            var payload: [String: Any] = [
                "draftUnitId": unit.id,
                "ringTag": unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines),
                "gender": unit.gender.rawValue,
                "acquisitionDate": ISO8601DateFormatter().string(from: unit.acquisitionDate),
                "purchaseCost": purchaseCost ?? NSNull(),
                "sellingPrice": sellingPrice,
                "supplier": unit.supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "notes": unit.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "mediaURLs": unitMediaURLsByID[unit.id] ?? [],
            ]
            if let subSubID = unit.subSubKindID { payload["subSubKindID"] = subSubID }
            if let subSubAr = unit.subSubKindNameAr { payload["subSubKindNameAr"] = subSubAr }
            if let subSubEn = unit.subSubKindNameEn { payload["subSubKindNameEn"] = subSubEn }
            if let itemID = unit.subSubKindItemID { payload["subSubKindItemID"] = itemID }
            if let itemAr = unit.subSubKindItemNameAr { payload["subSubKindItemNameAr"] = itemAr }
            if let itemEn = unit.subSubKindItemNameEn { payload["subSubKindItemNameEn"] = itemEn }
            return payload
        }

        let action: String
        let mutationProductID: String?
        let mutationCommandID: String?
        var mutationPayload: [String: Any]

        if productID.isEmpty {
            action = "create"
            mutationProductID = nil
            mutationCommandID = liveCreateCommandID
            mutationPayload = [
                "name": accessory.name ?? "",
                "nameEn": accessory.nameEn ?? "",
                "desc": accessory.desc ?? "",
                "descEn": accessory.descEn ?? "",
                "storeID": accessory.storeID ?? "",
                "price": basePrice,
                "sellPrice": basePrice,
                "finalPrice": liveInventoryMode == .individual ? basePrice : calculatedFinalPrice,
                "quantity": liveInventoryMode == .individual ? unitPayloads.count : max(1, quantity),
                "discountPercent": liveInventoryMode == .individual ? 0 : discountPercent,
                "discountAmount": liveInventoryMode == .individual ? 0 : discountAmount,
                "accessKindType": 3,
                "petMainCategoryID": accessory.petMainCategoryID,
                "petSubCategoryID": accessory.petSubCategoryID,
                "imageURLsArray": resolvedImageURLs,
                "isNew": true,
                "hasOffer": liveInventoryMode == .individual ? false : accessory.hasOffer,
                "showInAppMarket": !isDraft,
                "product_type": "live",
                "category": "Live Pets",
                "inventoryMode": liveInventoryMode.rawValue,
                "supplier": liveSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "arrivalDate": ISO8601DateFormatter().string(from: liveArrivalDate),
                "notes": liveIntakeNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                "reorderLevel": 5,
                "units": liveInventoryMode == .individual ? unitPayloads : [],
            ]
            if liveInventoryMode == .quantity && canViewStockCosts {
                mutationPayload["costPrice"] = groupCost
            }
            if liveInventoryMode == .individual {
                mutationPayload["standardSellingPrice"] = basePrice
            }
        } else if liveInventoryMode == .individual {
            action = "update_standard_selling_price"
            mutationProductID = productID
            mutationCommandID = PPLivePetInventoryService.commandID("standard-selling-price")
            mutationPayload = ["standardSellingPrice": basePrice]
        } else {
            action = "adjust"
            mutationProductID = productID
            mutationCommandID = PPLivePetInventoryService.commandID("group-adjustment")
            mutationPayload = [
                "adjustmentType": "manual",
                "targetQuantity": max(0, quantity),
                "reason": "catalog_editor_quantity_confirmation",
            ]
        }

        let successMessage = editingAccessory == nil
            ? Language.get("LivePet_Create_Success", alter: "تم إنشاء سجل الحيوان والمخزون بنجاح.")
            : Language.get("LivePet_Update_Success", alter: "تم تحديث بيانات الكتالوج والمخزون بنجاح.")

        do {
            let recovery = try makeLivePetRecovery(
                action: action,
                productID: mutationProductID,
                commandID: mutationCommandID,
                payload: mutationPayload,
                catalogValues: catalogValues,
                successMessage: successMessage,
                oldImageURLs: oldImageURLs
            )
            try persistLivePetRecovery(recovery)
            Task { @MainActor [weak self] in
                await self?.executeLivePetRecovery(recovery)
            }
        } catch {
            isSubmitting = false
            submissionFailureKind = .retryable
            errorMessage = localizedSubmissionFailure(for: error, kind: .retryable)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private var livePetRecoveryDefaultsKey: String {
        let actorUID = Auth.auth().currentUser?.uid ?? "signed-out"
        let operationScope = (editingAccessory?.accessoryID).flatMap { $0.isEmpty ? nil : $0 } ?? "new"
        return "PPAdmin.LivePetMutationRecovery.v1.\(actorUID).\(operationScope)"
    }

    private func makeLivePetRecovery(
        action: String,
        productID: String?,
        commandID: String?,
        payload: [String: Any],
        catalogValues: [String: Any],
        successMessage: String,
        oldImageURLs: [String]
    ) throws -> PPLivePetMutationRecovery {
        guard JSONSerialization.isValidJSONObject(payload),
              JSONSerialization.isValidJSONObject(catalogValues) else {
            throw PPLivePetServiceError.invalidResponse
        }
        return PPLivePetMutationRecovery(
            action: action,
            productID: productID,
            commandID: commandID,
            payloadData: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            catalogValuesData: try JSONSerialization.data(withJSONObject: catalogValues, options: [.sortedKeys]),
            catalogCommandID: PPLivePetInventoryService.commandID("catalog-metadata"),
            acceptedProductID: nil,
            acceptedRevision: nil,
            successMessage: successMessage,
            oldImageURLs: oldImageURLs
        )
    }

    private func dictionary(from data: Data) throws -> [String: Any] {
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PPLivePetServiceError.invalidResponse
        }
        return dictionary
    }

    private func applyLivePetRecovery(_ recovery: PPLivePetMutationRecovery) {
        livePetRecovery = recovery
        hasPendingLivePetRecovery = true
        pendingCatalogSyncProductID = recovery.acceptedProductID
        pendingCatalogSyncSuccessMessage = recovery.successMessage
        if recovery.action == "create", let commandID = recovery.commandID, !commandID.isEmpty {
            liveCreateCommandID = commandID
        }
    }

    private func persistLivePetRecovery(_ recovery: PPLivePetMutationRecovery) throws {
        let encoded = try JSONEncoder().encode(recovery)
        UserDefaults.standard.set(encoded, forKey: livePetRecoveryDefaultsKey)
        applyLivePetRecovery(recovery)
    }

    private func restoreLivePetRecoveryIfNeeded() {
        guard isLivePet,
              let encoded = UserDefaults.standard.data(forKey: livePetRecoveryDefaultsKey),
              let recovery = try? JSONDecoder().decode(PPLivePetMutationRecovery.self, from: encoded) else {
            return
        }
        applyLivePetRecovery(recovery)
        activeStage = .governance
        hasUnsavedChanges = true
        errorMessage = recovery.acceptedProductID == nil
            ? Language.get(
                "LivePet_Recovery_Unconfirmed",
                alter: "توجد عملية مخزون سابقة لم يُحسم تأكيدها. أعد المحاولة كما هي ليستخدم الخادم معرّف الأمر نفسه من دون إنشاء تكرار."
            )
            : Language.get(
                "LivePet_Recovery_CatalogPending",
                alter: "اعتمد الخادم عملية المخزون سابقاً. المتبقي فقط هو مزامنة عرض الكتالوج."
            )
    }

    private func clearLivePetRecovery() {
        UserDefaults.standard.removeObject(forKey: livePetRecoveryDefaultsKey)
        livePetRecovery = nil
        hasPendingLivePetRecovery = false
        pendingCatalogSyncProductID = nil
        pendingCatalogSyncSuccessMessage = nil
    }

    func discardChangesAndDismiss() {
        guard !preventsExplicitDismissal else { return }
        cleanupPendingPickedUploads()
        clearLivePetRecovery()
        onDismiss()
    }

    private func cleanupPendingPickedUploads() {
        let storageRoot = Storage.storage().reference().child("petAccessories")
        let uploadIDs = Set(pickedImageUploadIDs).union(pendingUnsavedUploads.values)
        for uploadID in uploadIDs {
            storageRoot.child("\(uploadID.uuidString).png").delete { _ in }
        }
        pickedImageUploadIDs.removeAll()
        pendingUnsavedUploads.removeAll()
        pendingSavedAccessoryDraft = nil
    }

    func dismissSubmissionFeedback() {
        errorMessage = nil
        submissionFailureKind = nil
    }

    var submissionFailureActionTitle: String? {
        guard let submissionFailureKind else { return nil }
        switch submissionFailureKind {
        case .denied:
            return Language.get("LivePet_SubmissionAction_Return", alter: "العودة إلى الكتالوج")
        case .conflict, .stale:
            return Language.get("LivePet_SubmissionAction_Refresh", alter: "تحديث الكتالوج")
        case .invalid:
            return Language.get("LivePet_SubmissionAction_Review", alter: "مراجعة الحقول")
        case .ambiguous, .retryable:
            return Language.get("LivePet_SubmissionAction_RetryExact", alter: "إعادة المحاولة دون تغيير")
        }
    }

    func performSubmissionFailureAction() {
        guard let submissionFailureKind else { return }
        switch submissionFailureKind {
        case .denied, .conflict, .stale:
            cleanupPendingPickedUploads()
            clearLivePetRecovery()
            errorMessage = nil
            self.submissionFailureKind = nil
            onDismiss()
        case .invalid:
            clearLivePetRecovery()
            errorMessage = nil
            self.submissionFailureKind = nil
            activeStage = .identity
        case .ambiguous, .retryable:
            errorMessage = nil
            self.submissionFailureKind = nil
            saveAccessory()
        }
    }

    private func executeLivePetRecovery(_ startingRecovery: PPLivePetMutationRecovery) async {
        var recovery = startingRecovery
        do {
            if recovery.acceptedProductID == nil {
                let payload = try dictionary(from: recovery.payloadData)
                let response = try await PPLivePetInventoryService.callInventory(
                    action: recovery.action,
                    productID: recovery.productID,
                    commandID: recovery.commandID,
                    payload: payload
                )
                let acceptedProductID: String
                if recovery.action == "create" {
                    acceptedProductID = PPLivePetInventoryService.string(response["productId"])
                    if response["idempotent"] as? Bool == true {
                        recovery.successMessage = Language.get(
                            "LivePet_Create_Replay_Success",
                            alter: "أكد الخادم وجود صنف الكتالوج والمخزون الحي من المحاولة السابقة، ولم يُنشأ سجل مكرر."
                        )
                    }
                } else {
                    acceptedProductID = recovery.productID ?? ""
                }
                guard !acceptedProductID.isEmpty else {
                    throw PPLivePetServiceError.invalidResponse
                }
                recovery.acceptedProductID = acceptedProductID
                let acceptedRevision = PPLivePetInventoryService.integer(response["revision"])
                recovery.acceptedRevision = acceptedRevision > 0 ? acceptedRevision : nil
                try persistLivePetRecovery(recovery)
            }

            guard let acceptedProductID = recovery.acceptedProductID, !acceptedProductID.isEmpty else {
                throw PPLivePetServiceError.invalidResponse
            }
            let catalogValues = try dictionary(from: recovery.catalogValuesData)
            let catalogResponse = try await PPLivePetInventoryService.updateCatalogPresentation(
                productID: acceptedProductID,
                values: catalogValues,
                commandID: recovery.catalogCommandID ?? "\(recovery.commandID ?? acceptedProductID)-catalog",
                expectedRevision: recovery.acceptedRevision
            )
            let confirmedRevision = PPLivePetInventoryService.integer(catalogResponse["revision"])
            let confirmedProduct = try await PPLivePetInventoryService.readProduct(
                productID: acceptedProductID,
                minimumRevision: confirmedRevision
            )

            let retainedURLs = confirmedProduct.imageURLsArray ?? []
            let confirmedSuccessMessage = recovery.successMessage
            clearLivePetRecovery()
            cleanupRemovedImages(oldImageURLs: recovery.oldImageURLs, retainedURLs: retainedURLs)
            if editingAccessory != nil {
                commitSavedAccessory(confirmedProduct)
            } else {
                commitConfirmedLivePetForm(retainedURLs: retainedURLs)
            }
            if liveInventoryMode == .quantity {
                persistCommerceRecord(for: acceptedProductID)
            }
            completeSuccessfulSave(message: confirmedSuccessMessage)
        } catch {
            isSubmitting = false
            if recovery.acceptedProductID != nil {
                try? persistLivePetRecovery(recovery)
                submissionFailureKind = nil
                let detail = PPLivePetInventoryService.localizedMessage(for: error)
                errorMessage = String(
                    format: Language.get(
                        "LivePet_CatalogSync_Pending_Format",
                        alter: "اعتمد الخادم عملية المخزون، لكن تعذر مزامنة عرض الكتالوج. لا تغيّر البيانات؛ أعد محاولة المزامنة. التفاصيل: %@"
                    ),
                    detail
                )
            } else {
                let kind = submissionFailureKind(for: error)
                if kind.preservesExactRecovery {
                    try? persistLivePetRecovery(recovery)
                } else {
                    clearLivePetRecovery()
                }
                submissionFailureKind = kind
                errorMessage = localizedSubmissionFailure(for: error, kind: kind)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func submissionFailureKind(for error: Error) -> PPLivePetSubmissionFailureKind {
        let nsError = error as NSError
        let details = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]
        let domainCode = PPLivePetInventoryService.string(details["domainCode"]).uppercased()

        if domainCode.contains("PERMISSION") || domainCode.contains("UNAUTHENTICATED") {
            return .denied
        }
        if domainCode.contains("NOT_FOUND") || domainCode.contains("STALE")
            || domainCode.contains("STATUS_CHANGED") || domainCode.contains("BRANCH_MISMATCH")
            || domainCode.contains("UNAVAILABLE") {
            return .stale
        }
        if domainCode.contains("CONFLICT") || domainCode.contains("ALREADY_EXISTS") {
            return .conflict
        }

        if nsError.domain == "com.firebase.functions" {
            switch nsError.code {
            case 7, 16:
                return .denied
            case 6, 9, 10:
                return .conflict
            case 3:
                return .invalid
            case 5:
                return .stale
            case 1, 4, 14:
                return .ambiguous
            case 8, 13:
                return .retryable
            default:
                return .ambiguous
            }
        }
        if nsError.domain == NSURLErrorDomain {
            return .ambiguous
        }
        return .retryable
    }

    private func localizedSubmissionFailure(
        for error: Error,
        kind: PPLivePetSubmissionFailureKind
    ) -> String {
        let nsError = error as NSError
        let details = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]
        let domainCode = PPLivePetInventoryService.string(details["domainCode"])
        let reference = domainCode.isEmpty ? "\(nsError.domain):\(nsError.code)" : domainCode
        let format: String
        switch kind {
        case .denied:
            format = Language.get(
                "LivePet_Submission_Denied_Format",
                alter: "لم يسمح الخادم بهذه العملية. لا تغيّر الصلاحيات من التطبيق؛ راجع مسؤول الوصول. المرجع: %@"
            )
        case .conflict:
            format = Language.get(
                "LivePet_Submission_Conflict_Format",
                alter: "تعارضت العملية مع حالة أحدث أو أمر سابق. حدّث الكتالوج قبل أي تعديل جديد. المرجع: %@"
            )
        case .invalid:
            format = Language.get(
                "LivePet_Submission_Invalid_Format",
                alter: "رفض الخادم إحدى القيم. راجع الحقول وحدودها ثم أرسل من جديد. المرجع: %@"
            )
        case .stale:
            format = Language.get(
                "LivePet_Submission_Stale_Format",
                alter: "تغير السجل على الخادم أو لم يعد متاحاً. ارجع إلى الكتالوج وحدّث البيانات. المرجع: %@"
            )
        case .ambiguous:
            format = Language.get(
                "LivePet_Submission_Ambiguous_Format",
                alter: "انقطع التأكيد بعد إرسال العملية. لا تنشئ أمراً جديداً؛ أعد المحاولة كما هي ليُستخدم معرّف الأمر نفسه. المرجع: %@"
            )
        case .retryable:
            format = Language.get(
                "LivePet_Submission_Retryable_Format",
                alter: "تعذر إكمال العملية مؤقتاً. احتُفظ بالطلب نفسه لإعادة المحاولة الآمنة. المرجع: %@"
            )
        }
        return String(format: format, reference)
    }

    private func cleanupRemovedImages(oldImageURLs: [String], retainedURLs: [String]) {
        let retained = Set(retainedURLs)
        for oldURL in oldImageURLs where !oldURL.isEmpty && !retained.contains(oldURL) {
            if let reference = try? Storage.storage().reference(forURL: oldURL) {
                reference.delete { _ in }
            }
        }
    }
}

// MARK: - Bilingual Language & Reusable Input Components

enum PPBilingualLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .arabic: return "AR"
        case .english: return "EN"
        }
    }

    var shortTitle: String {
        switch self {
        case .arabic: return Language.get("Bilingual_ArabicShort", alter: "عربي")
        case .english: return Language.get("Bilingual_EnglishShort", alter: "EN")
        }
    }

    var fullTitle: String {
        switch self {
        case .arabic: return Language.get("Bilingual_ArabicFull", alter: "العربية")
        case .english: return Language.get("Bilingual_EnglishFull", alter: "الإنجليزية")
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .arabic: return .rightToLeft
        case .english: return .leftToRight
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .arabic: return .trailing
        case .english: return .leading
        }
    }
}

// MARK: - Bilingual Segmented Switcher Capsule

struct PPBilingualSegmentedCapsule: View {
    @Binding var selectedLanguage: PPBilingualLanguage
    let hasArabicText: Bool
    let hasEnglishText: Bool

    var body: some View {
        HStack(spacing: 2) {
            segmentButton(for: .arabic, hasText: hasArabicText)
            segmentButton(for: .english, hasText: hasEnglishText)
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(uiColor: .systemGray6).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func segmentButton(for lang: PPBilingualLanguage, hasText: Bool) -> some View {
        let isSelected = (selectedLanguage == lang)
        Button {
            if selectedLanguage != lang {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedLanguage = lang
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } label: {
            HStack(spacing: 4) {
                // Status dot indicator
                if hasText {
                    Circle()
                        .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255), lineWidth: 1.2)
                        .frame(width: 5, height: 5)
                }

                Text(lang.shortTitle)
                    .font(isSelected ? AdminType.caption1Bold : AdminType.caption1)
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .fill(AdminSurface.surface)
                            .shadow(color: Color.black.opacity(0.12), radius: 2.5, x: 0, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                    .strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 0.75)
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Forced Keyboard Language Helpers

enum PPKeyboardLanguage {
    case arabic
    case english

    var code: String {
        switch self {
        case .arabic: return "ar"
        case .english: return "en"
        }
    }

    var identifier: String {
        switch self {
        case .arabic: return "pp_force_ar"
        case .english: return "pp_force_en"
        }
    }
}

private final class PPKeyboardLanguageProbeView: UIView {
    var onAttach: ((UIView) -> Void)?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil {
            onAttach?(self)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttach?(self)
        }
    }
}

private struct PPKeyboardLanguageIntrospector: UIViewRepresentable {
    let language: PPKeyboardLanguage

    func makeUIView(context: Context) -> PPKeyboardLanguageProbeView {
        let view = PPKeyboardLanguageProbeView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.onAttach = { [language] probe in
            Self.apply(from: probe, language: language)
        }
        return view
    }

    func updateUIView(_ uiView: PPKeyboardLanguageProbeView, context: Context) {
        uiView.onAttach = { [language] probe in
            Self.apply(from: probe, language: language)
        }
        DispatchQueue.main.async {
            Self.apply(from: uiView, language: language)
        }
    }

    static func apply(from probe: UIView, language: PPKeyboardLanguage) {
        let langCode = language.code
        let ident = language.identifier

        var current: UIView? = probe
        while let parent = current?.superview {
            if let tf = findTextField(in: parent) {
                let needsCycle = tf.isFirstResponder && tf.pp_forcedKeyboardLanguage != langCode
                tf.pp_forcedKeyboardLanguage = langCode
                tf.accessibilityIdentifier = ident
                if language == .english {
                    tf.keyboardType = .asciiCapable
                }
                if needsCycle {
                    tf.resignFirstResponder()
                    tf.becomeFirstResponder()
                }
                return
            }
            if let tv = findTextView(in: parent) {
                let needsCycle = tv.isFirstResponder && tv.pp_forcedKeyboardLanguage != langCode
                tv.pp_forcedKeyboardLanguage = langCode
                tv.accessibilityIdentifier = ident
                if needsCycle {
                    tv.resignFirstResponder()
                    tv.becomeFirstResponder()
                }
                return
            }
            current = parent
        }
    }

    private static func findTextField(in root: UIView) -> UITextField? {
        if let tf = root as? UITextField { return tf }
        for sub in root.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }

    private static func findTextView(in root: UIView) -> UITextView? {
        if let tv = root as? UITextView { return tv }
        for sub in root.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}

extension View {
    func forceKeyboardLanguage(_ language: PPKeyboardLanguage) -> some View {
        self
            .accessibilityIdentifier(language.identifier)
            .background(PPKeyboardLanguageIntrospector(language: language))
    }
}

// MARK: - Bilingual Single-Line Input Field

struct PPBilingualInputField: View {
    let title: String
    let isRequired: Bool
    @Binding var arabicText: String
    @Binding var englishText: String
    let arabicPlaceholder: String
    let englishPlaceholder: String
    @Binding var selectedLanguage: PPBilingualLanguage
    let isFocused: Bool
    var onFocusChange: ((Bool) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isArabicFocused: Bool
    @FocusState private var isEnglishFocused: Bool

    private var hasArabicText: Bool {
        !arabicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasEnglishText: Bool {
        !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFieldFocused: Bool {
        isArabicFocused || isEnglishFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            // Label Header Row with Integrated Switcher
            HStack(alignment: .center, spacing: AdminSpacing.sm) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                    if isRequired {
                        Text("*")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color.red)
                    }
                }

                Spacer()

                PPBilingualSegmentedCapsule(
                    selectedLanguage: $selectedLanguage,
                    hasArabicText: hasArabicText,
                    hasEnglishText: hasEnglishText
                )
            }

            // Single-Footprint Input Box (Smooth AR / EN state flip)
            ZStack(alignment: .center) {
                TextField(arabicPlaceholder, text: $arabicText)
                    .font(AdminType.body)
                    .focused($isArabicFocused)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.leading)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { onSubmit?() }
                    .forceKeyboardLanguage(.arabic)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(selectedLanguage == .arabic ? 1 : 0)
                    .allowsHitTesting(selectedLanguage == .arabic)

                TextField(englishPlaceholder, text: $englishText)
                    .font(AdminType.body)
                    .focused($isEnglishFocused)
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(.leading)
                    .textContentType(.name)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.next)
                    .onSubmit { onSubmit?() }
                    .forceKeyboardLanguage(.english)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(selectedLanguage == .english ? 1 : 0)
                    .allowsHitTesting(selectedLanguage == .english)
            }
            .padding(.horizontal, AdminSpacing.md)
            .frame(minHeight: AdminTouchTarget.expanded)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder((isFocused || isFieldFocused) ? AdminSurface.primary : AdminSurface.hairline.opacity(0.7), lineWidth: (isFocused || isFieldFocused) ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .onTapGesture {
                if !isFieldFocused {
                    if selectedLanguage == .arabic {
                        isArabicFocused = true
                    } else {
                        isEnglishFocused = true
                    }
                }
            }
            .onChange(of: isArabicFocused) { _ in
                onFocusChange?(isFieldFocused)
            }
            .onChange(of: isEnglishFocused) { _ in
                onFocusChange?(isFieldFocused)
            }
            .onChange(of: isFocused) { focused in
                if focused {
                    if selectedLanguage == .arabic {
                        isArabicFocused = true
                    } else {
                        isEnglishFocused = true
                    }
                } else {
                    isArabicFocused = false
                    isEnglishFocused = false
                }
            }
            .onChange(of: selectedLanguage) { newLang in
                if isFieldFocused {
                    // Seamless direct focus transition without dropping keyboard
                    if newLang == .arabic {
                        isArabicFocused = true
                        isEnglishFocused = false
                    } else {
                        isEnglishFocused = true
                        isArabicFocused = false
                    }
                }
            }

            // Status & Quick Action Strip
            bilingualStatusStrip
        }
    }

    @ViewBuilder
    private var bilingualStatusStrip: some View {
        HStack(spacing: 6) {
            if hasArabicText && hasEnglishText {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Text(Language.get("Bilingual_BothComplete", alter: "مكتمل باللغتين (العربية والإنجليزية)"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            } else if hasArabicText && !hasEnglishText {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedLanguage = .english
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    isEnglishFocused = true
                    isArabicFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 245/255, green: 158/255, blue: 11/255))
                            .frame(width: 5, height: 5)
                        Text(Language.get("Bilingual_EnglishMissingAction", alter: "الإنجليزية مفقودة • انقر للإضافة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if !hasArabicText && hasEnglishText {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedLanguage = .arabic
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    isArabicFocused = true
                    isEnglishFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 239/255, green: 68/255, blue: 68/255))
                            .frame(width: 5, height: 5)
                        Text(Language.get("Bilingual_ArabicMissingAction", alter: "العربية مطلوبة • انقر للإضافة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()

            let currentCount = selectedLanguage == .arabic ? arabicText.count : englishText.count
            if currentCount > 0 {
                Text(verbatim: "\(currentCount.englishDigits)/90")
                    .font(AdminType.caption2)
                    .foregroundStyle(currentCount > 90 ? Color.red : AdminSurface.secondaryText.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.top, 1)
    }
}

// MARK: - Bilingual Multi-Line TextEditor Field

struct PPBilingualTextEditorField: View {
    let title: String
    let isRequired: Bool
    @Binding var arabicText: String
    @Binding var englishText: String
    let arabicPlaceholder: String
    let englishPlaceholder: String
    @Binding var selectedLanguage: PPBilingualLanguage
    var minHeight: CGFloat = 100
    let isFocused: Bool
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isArabicFocused: Bool
    @FocusState private var isEnglishFocused: Bool

    private var hasArabicText: Bool {
        !arabicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasEnglishText: Bool {
        !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFieldFocused: Bool {
        isArabicFocused || isEnglishFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            // Label Header Row with Integrated Switcher
            HStack(alignment: .center, spacing: AdminSpacing.sm) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                    if isRequired {
                        Text("*")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color.red)
                    }
                }

                Spacer()

                PPBilingualSegmentedCapsule(
                    selectedLanguage: $selectedLanguage,
                    hasArabicText: hasArabicText,
                    hasEnglishText: hasEnglishText
                )
            }

            // Single-Footprint Multiline Editor (Smooth AR / EN state flip)
            ZStack(alignment: .top) {
                // Arabic Editor Layer
                ZStack(alignment: .topLeading) {
                    if arabicText.isEmpty {
                        Text(arabicPlaceholder)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.65))
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AdminSpacing.md)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $arabicText)
                        .font(AdminType.body)
                        .focused($isArabicFocused)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                        .padding(AdminSpacing.xs)
                        .scrollContentBackgroundIfAvailable()
                        .forceKeyboardLanguage(.arabic)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .contentShape(Rectangle())
                .opacity(selectedLanguage == .arabic ? 1 : 0)
                .allowsHitTesting(selectedLanguage == .arabic)

                // English Editor Layer
                ZStack(alignment: .topLeading) {
                    if englishText.isEmpty {
                        Text(englishPlaceholder)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.65))
                            .environment(\.layoutDirection, .leftToRight)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AdminSpacing.md)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $englishText)
                        .font(AdminType.body)
                        .focused($isEnglishFocused)
                        .environment(\.layoutDirection, .leftToRight)
                        .multilineTextAlignment(.leading)
                        .keyboardType(.asciiCapable)
                        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                        .padding(AdminSpacing.xs)
                        .scrollContentBackgroundIfAvailable()
                        .forceKeyboardLanguage(.english)
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .contentShape(Rectangle())
                .opacity(selectedLanguage == .english ? 1 : 0)
                .allowsHitTesting(selectedLanguage == .english)
            }
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder((isFocused || isFieldFocused) ? AdminSurface.primary : AdminSurface.hairline.opacity(0.7), lineWidth: (isFocused || isFieldFocused) ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .onTapGesture {
                if !isFieldFocused {
                    if selectedLanguage == .arabic {
                        isArabicFocused = true
                    } else {
                        isEnglishFocused = true
                    }
                }
            }
            .onChange(of: isArabicFocused) { _ in
                onFocusChange?(isFieldFocused)
            }
            .onChange(of: isEnglishFocused) { _ in
                onFocusChange?(isFieldFocused)
            }
            .onChange(of: isFocused) { focused in
                if focused {
                    if selectedLanguage == .arabic {
                        isArabicFocused = true
                    } else {
                        isEnglishFocused = true
                    }
                } else {
                    isArabicFocused = false
                    isEnglishFocused = false
                }
            }
            .onChange(of: selectedLanguage) { newLang in
                if isFieldFocused {
                    // Seamless direct focus transition without dropping keyboard
                    if newLang == .arabic {
                        isArabicFocused = true
                        isEnglishFocused = false
                    } else {
                        isEnglishFocused = true
                        isArabicFocused = false
                    }
                }
            }

            // Status & Quick Action Strip
            bilingualStatusStrip
        }
    }

    @ViewBuilder
    private var bilingualStatusStrip: some View {
        HStack(spacing: 6) {
            if hasArabicText && hasEnglishText {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Text(Language.get("Bilingual_BothComplete", alter: "مكتمل باللغتين (العربية والإنجليزية)"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            } else if hasArabicText && !hasEnglishText {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedLanguage = .english
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    isEnglishFocused = true
                    isArabicFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 245/255, green: 158/255, blue: 11/255))
                            .frame(width: 5, height: 5)
                        Text(Language.get("Bilingual_DescEnglishMissingAction", alter: "الوصف بالإنجليزي مفقود • انقر للإضافة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if !hasArabicText && hasEnglishText {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedLanguage = .arabic
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    isArabicFocused = true
                    isEnglishFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 239/255, green: 68/255, blue: 68/255))
                            .frame(width: 5, height: 5)
                        Text(Language.get("Bilingual_DescArabicMissingAction", alter: "الوصف بالعربي غير مدخل • انقر للإضافة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 1)
    }
}

// MARK: - Reimagined Flagship Screen

struct PPAccessoryEditorScreen: View {
    @StateObject var viewModel: PPAccessoryEditorViewModel
    @FocusState private var focusedField: FormField?
    @Namespace private var stageAnimation
    @State private var showQuantityAlert: Bool = false
    @State private var showPricePad: Bool = false
    @State private var showDiscountPad: Bool = false
    @State private var quantityAlertText: String = ""
    @State private var bilingualLanguage: PPBilingualLanguage = .arabic
    
    enum FormField: Hashable {
        case name, desc, price, discountPercent, discountAmount, quantity, passport, weight, wholesalePrice
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Ambient Spatial Canvas Background
            AdminSurface.background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            VStack(spacing: 0) {
                // Scrollable Master Canvas
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Top Sovereign Command Header
                            sovereignHeaderView

                            // Spatial Stage Navigation Radar
                            stageRadarView
                                .padding(.horizontal, AdminSpacing.screenMargin)
                                .padding(.bottom, 8)

                            LazyVStack(spacing: 16) {
                                // Archetype Selector (when applicable)
                                if viewModel.showTypeRow && viewModel.editingAccessory == nil {
                                    archetypeSelectorDeck
                                }

                                // Interactive Digital Twin Hologram
                                digitalTwinHologramDeck

                                // Dynamic Stage Sections
                                switch viewModel.activeStage {
                                case .identity:
                                    identityStageCanvas
                                case .bioVault:
                                    bioVaultStageCanvas
                                case .pricing:
                                    pricingStageCanvas
                                case .governance:
                                    governanceStageCanvas
                                }
                            }
                            .padding(.horizontal, AdminSpacing.screenMargin)
                            .padding(.top, 6)
                            .padding(.bottom, 130)
                        }
                    }
                    .scrollDismissesKeyboardCompat()
                    .onChange(of: focusedField) { field in
                        guard let field = field else { return }
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                    .onChange(of: bilingualLanguage) { _ in
                        guard let field = focusedField else { return }
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            withAnimation(.easeOut(duration: 0.20)) {
                                proxy.scrollTo(field, anchor: .center)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                proxy.scrollTo(field, anchor: .center)
                            }
                        }
                    }
                }
            }

            // Floating Tactical Save Dock
            tacticalSaveDock
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.showImagePicker) {
            PPImagePickerSheet(maxSelection: 9 - viewModel.totalImageCount) { images in
                viewModel.addPickedImages(images)
            }
        }
        .sheet(isPresented: $viewModel.showSpeciesPicker) {
            PPAccessorySpeciesPickerSheet(
                speciesList: viewModel.availableMainKinds,
                selectedSpecies: viewModel.selectedMainKind,
                onSelect: { species in
                    viewModel.selectedMainKind = species
                    viewModel.showSpeciesPicker = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showBreedPicker) {
            PPAccessoryBreedPickerSheet(
                breedList: viewModel.availableSubKinds,
                selectedBreed: viewModel.selectedSubKind,
                onSelect: { breed in
                    viewModel.selectedSubKind = breed
                    viewModel.showBreedPicker = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showStorePicker) {
            PPBranchSelectionGateView(
                title: Language.isRTL() ? "اختر الفرع المالك" : "Select Owning Branch",
                subtitle: Language.isRTL() ? "سينسب الصنف والمخزون إلى هذا الفرع." : "Inventory and operations will be assigned to this branch.",
                selectedBranchID: viewModel.selectedStoreID,
                allowGlobalAccess: false
            ) { selectedBranch in
                viewModel.selectedStoreID = selectedBranch.branchID
                viewModel.selectedStoreName = selectedBranch.localizedName()
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $viewModel.showQuantityGroupInspector) {
            if let group = viewModel.selectedQuantityGroupForEditing {
                PPQuantityGroupInspectorSheet(
                    group: group,
                    canManageWholesale: viewModel.canManageWholesale,
                    onSave: { updated in
                        viewModel.saveQuantityGroup(updated)
                    },
                    onDelete: viewModel.quantityGroups.count > 1 ? {
                        viewModel.deleteQuantityGroup(id: group.id)
                    } : nil
                )
            }
        }
        .tactileQuantityPad(
            isPresented: $showQuantityAlert,
            title: Language.get("EditQuantity", alter: "تعديل الكمية"),
            currentQuantity: viewModel.quantity,
            referenceQuantity: viewModel.quantity,
            specimen: PPTactileSpecimenInfo(
                title: viewModel.name.isEmpty ? (viewModel.nameEn.isEmpty ? Language.get("Product", alter: "منتج") : viewModel.nameEn) : viewModel.name,
                sku: viewModel.sku,
                barcode: viewModel.barcode,
                unitCost: Double(viewModel.costPriceText)
            )
        ) { newQty in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                viewModel.quantity = max(0, newQty)
            }
        }
        .tactilePricePad(
            isPresented: $showPricePad,
            title: Language.get("EditPrice", alter: "تعديل السعر"),
            currentPrice: Double(viewModel.priceText.replacingOccurrences(of: ",", with: ".")) ?? 0.0,
            referencePrice: Double(viewModel.priceText.replacingOccurrences(of: ",", with: ".")),
            specimen: PPTactileSpecimenInfo(
                title: viewModel.name.isEmpty ? (viewModel.nameEn.isEmpty ? Language.get("Product", alter: "منتج") : viewModel.nameEn) : viewModel.name,
                sku: viewModel.sku,
                barcode: viewModel.barcode,
                unitCost: Double(viewModel.costPriceText)
            )
        ) { newPrice in
            viewModel.priceText = String(format: "%.2f", newPrice)
        }
        .sheet(isPresented: $showDiscountPad) {
            PPTactileNumberPadSheet(
                config: PPTactileNumberPadConfig(
                    title: Language.get("DiscountPercent", alter: "نسبة الخصم"),
                    subtitle: viewModel.name,
                    mode: .percentage(maxLimit: 100),
                    initialValue: Double(viewModel.discountPercentText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
                )
            ) { newDiscount in
                viewModel.discountPercentText = String(format: "%.1f", newDiscount)
            }
        }
    }

    private func promptQuantityEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showQuantityAlert = true
    }

    private func showDiscardAlert() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Discard_Changes_Title", alter: "تنبيه"),
            subtitle: Language.get("Discard_Changes_Message", alter: "هل أنت متأكد من رغبتك في المغادرة؟ ستفقد كافة التعديلات غير المحفوظة."),
            confirmButton: Language.get("Discard_Changes_Confirm", alter: "مغادرة وتجاهل"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
            guard didConfirm else { return }
            viewModel.discardChangesAndDismiss()
            },
            cancelBlock: nil
        )
    }

    // MARK: - 1. Sovereign Command Navigation Bar

    private var sovereignHeaderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdminSovereignNavigationBar(
                title: viewModel.screenTitle,
                subtitle: viewModel.eyebrowKindText,
                statusDotColor: viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess),
                onBack: {
                    if viewModel.hasUnsavedChanges {
                        showDiscardAlert()
                    } else {
                        viewModel.discardChangesAndDismiss()
                    }
                }
            ) {
                // Primary Save Pill
                AdminPrimaryPillButton(
                    title: Language.get("Save", alter: "حفظ"),
                    systemImage: "checkmark",
                    isLoading: viewModel.isSubmitting
                ) {
                    viewModel.saveAccessory()
                }
            }

            // Dynamic Error or Success Messages
            if let err = viewModel.errorMessage {
                AdminErrorBanner(message: err) {
                    viewModel.errorMessage = nil
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 2)
            } else if let success = viewModel.saveSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color(uiColor: .ppSuccess))
                    Text(success)
                        .font(AdminType.calloutBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - 2. Spatial Stage Navigation Radar

    private var stageRadarView: some View {
        HStack(spacing: 6) {
            ForEach(PPEditorStage.allCases) { stage in
                let isSelected = viewModel.activeStage == stage
                let isDone = viewModel.isStageComplete(stage)

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.activeStage = stage
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isDone && !isSelected ? "checkmark.circle.fill" : stage.symbol)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : (isDone ? Color(uiColor: .ppSuccess) : AdminCommandInk.secondary))

                        Text(stage.localizedTitle(isLivePet: viewModel.isLivePet))
                            .font(isSelected ? AdminType.captionBold : AdminType.caption2)
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AdminSurface.primary)
                                    .matchedGeometryEffect(id: "ActiveStagePill", in: stageAnimation)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AdminSurface.control)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    // MARK: - 3. Interactive Digital Twin Hologram

    private var digitalTwinHologramDeck: some View {
        VStack(spacing: 10) {
            // Viewport Mode Switcher (Marketplace vs POS)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("DigitalTwinLabel", alter: "المعاينة الحية والتفاعل"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer()

                // Flip Mode Pills
                HStack(spacing: 4) {
                    twinModeButton(mode: .marketplace, icon: "iphone")
                    twinModeButton(mode: .posTerminal, icon: "barcode.viewfinder")
                }
                .padding(3)
                .background(AdminSurface.control, in: Capsule())
            }

            // The Interactive Hologram Card
            if viewModel.digitalTwinMode == .marketplace {
                marketplaceTwinCard
            } else {
                posTerminalTwinCard
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AdminSurface.surface, AdminSurface.surface.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private func twinModeButton(mode: PPDigitalTwinMode, icon: String) -> some View {
        let isSelected = viewModel.digitalTwinMode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.digitalTwinMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(width: 28, height: 24)
                .background(
                    isSelected ? AnyView(Capsule().fill(AdminSurface.primary)) : AnyView(Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // Consumer Marketplace Digital Twin Card
    private var marketplaceTwinCard: some View {
        HStack(spacing: 14) {
            // Photo Hologram Frame
            ZStack(alignment: .bottomLeading) {
                if let firstPicked = viewModel.pickedImages.first {
                    Image(uiImage: firstPicked)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let firstURL = viewModel.existingImageURLs.first, let url = URL(string: firstURL) {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 82, height: 82)) {
                        Image(systemName: "photo.fill").foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .frame(width: 82, height: 82)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 82, height: 82)
                        .overlay(
                            Image(systemName: viewModel.isLivePet ? "pawprint.fill" : (viewModel.isFood ? "fork.knife" : "bag.fill"))
                                .font(.system(size: 26))
                                .foregroundStyle(AdminSurface.primary.opacity(0.5))
                        )
                }

                // Media Count Capsule
                if viewModel.totalImageCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 8))
                        Text(verbatim: viewModel.totalImageCount.englishDigits)
                            .font(PPBrandFont.bold(size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(5)
                }
            }

            // Information Projection
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.selectedCategoryDisplayTitle ?? Language.get("General", alter: "عام"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))

                    if let breed = viewModel.selectedSubKind?.subKindName {
                        Text("• \(breed)")
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    Spacer()

                    // Biological Gender Icon (for live pets)
                    if viewModel.isLivePet {
                        genderIconBadge(viewModel.selectedGender)
                    }
                }

                Text(viewModel.name.isEmpty ? Language.get("ItemNamePlaceholder", alter: "اسم الحيوان أو المنتج") : viewModel.name)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                // Bio-Security Micro Tags (when live pet)
                if viewModel.isLivePet {
                    HStack(spacing: 4) {
                        if viewModel.isVaccinated {
                            microHealthPill(title: "محصن", icon: "cross.case.fill", color: Color(uiColor: .ppSuccess))
                        }
                        if viewModel.isDewormed {
                            microHealthPill(title: "وقائي", icon: "shield.fill", color: Color(uiColor: .ppSuccess))
                        }
                        if viewModel.isMicrochipped {
                            microHealthPill(title: "شريحة", icon: "cpu.fill", color: Color.blue)
                        }
                    }
                }

                // Pricing Readout
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: viewModel.formattedFinalPrice.normalizedEnglishDigits)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primary)
                        .monospacedDigit()

                    if viewModel.calculatedFinalPrice < viewModel.basePrice && viewModel.basePrice > 0 {
                        Text(verbatim: String(format: "%.0f %@", viewModel.basePrice, Language.get("QAR", alter: "ر.ق")).normalizedEnglishDigits)
                            .strikethrough(true, color: Color.gray)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminCommandInk.tertiary)
                    }
                }
            }
            Spacer()
        }
    }

    // Cashier POS Digital Twin Card
    private var posTerminalTwinCard: some View {
        HStack(spacing: 12) {
            // Monospace Barcode Simulation & Unit Indicator
            VStack(spacing: 4) {
                Image(systemName: "barcode")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(verbatim: (viewModel.isIndividualLivePet ? (viewModel.livePetUnits.first?.ringTag.isEmpty == false ? viewModel.livePetUnits.first!.ringTag : "RING-TAG") : "BATCH-SKU").normalizedEnglishDigits)
                    .font(PPBrandFont.bold(size: 9))
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .frame(width: 86, height: 82)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.get("POSTerminalPreview", alter: "نظام نقطة البيع (POS)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                    Spacer()
                    Text(verbatim: (viewModel.isIndividualLivePet ? "\(viewModel.livePetUnits.count.englishDigits) سجل فردي" : "كمية: \(viewModel.quantity.englishDigits)").normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }

                Text(viewModel.name.isEmpty ? Language.get("ItemNamePlaceholder", alter: "اسم الحيوان أو المنتج") : viewModel.name)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(Language.get("POSStoreLabel", alter: "الفرع: ") + viewModel.selectedStoreName)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack {
                    Text(Language.get("POSTerminalPrice", alter: "سعر المحاسبة:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(verbatim: viewModel.formattedFinalPrice.normalizedEnglishDigits)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                }
            }
            Spacer()
        }
    }

    private func genderIconBadge(_ gender: String) -> some View {
        let symbol: String
        let color: Color
        switch gender {
        case "female":
            symbol = "♀"
            color = .pink
        case "pair":
            symbol = "⚥"
            color = .purple
        default:
            symbol = "♂"
            color = .blue
        }
        return Text(symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(color)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.12), in: Circle())
    }

    private func microHealthPill(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(title)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.10), in: Capsule())
    }

    // MARK: - 4. Archetype Selector

    private var archetypeSelectorDeck: some View {
        HStack(spacing: 8) {
            archetypePill(kind: .typeAccessory, title: Language.get("Accessory", alter: "إكسسوار"), icon: "bag.fill")
            archetypePill(kind: .typeFood, title: Language.get("Food", alter: "أغذية ومكملات"), icon: "fork.knife")
            archetypePill(kind: .typeLivePets, title: Language.get("Live pets", alter: "حيوان حي"), icon: "pawprint.fill")
        }
        .padding(6)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private func archetypePill(kind: AccessKindType, title: String, icon: String) -> some View {
        let isSelected = viewModel.selectedKind == kind
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.selectedKind = kind
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                Text(title)
                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)
            }
            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                isSelected
                    ? AnyView(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AdminSurface.primary).shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2))
                    : AnyView(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. STAGE 1: Identity & Visual Vault Canvas

    private var identityStageCanvas: some View {
        VStack(spacing: 16) {
            // Studio Media Deck
            mediaAssetVaultDeck

            // Core Nomenclature & Description
            coreInformationDeck

            // Taxonomy & Classification
            taxonomyClassificationDeck
        }
    }

    private var mediaAssetVaultDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("MediaVault", alter: "معرض الصور والوسائط"), systemImage: "photo.stack.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text(verbatim: "\(viewModel.totalImageCount.englishDigits)/9 " + Language.get("Photos", alter: "صور"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Photo Action Slot
                    if viewModel.canAddImages {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.showImagePicker = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.badge.ellipsis")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(AdminSurface.primary)
                                Text(Language.get("AddPhoto", alter: "إضافة صورة"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .frame(width: 92, height: 92)
                            .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundStyle(AdminSurface.primary.opacity(0.40))
                            )
                        }
                        .buttonStyle(EditorPressStyle())
                    }

                    // Newly Picked Images
                    ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, uiImage in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            // Star Badge for Primary Photo
                            if index == 0 && viewModel.existingImageURLs.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.yellow)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }

                            Button {
                                viewModel.removePickedImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color.red)
                                    .padding(4)
                            }
                        }
                    }

                    // Existing URLs
                    ForEach(Array(viewModel.existingImageURLs.enumerated()), id: \.offset) { index, urlString in
                        ZStack(alignment: .topTrailing) {
                            if let url = URL(string: urlString) {
                                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 92, height: 92)) {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 92, height: 92)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }

                            if index == 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.yellow)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }

                            Button {
                                viewModel.removeExistingImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color.red)
                                    .padding(4)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private var coreInformationDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Language.get("CoreInfo", alter: "البيانات الأساسية للصنف"), systemImage: "pencil.and.outline")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            PPBilingualInputField(
                title: Language.get("ItemName", alter: "اسم الصنف أو الحيوان"),
                isRequired: true,
                arabicText: $viewModel.name,
                englishText: $viewModel.nameEn,
                arabicPlaceholder: Language.get("EnterItemName", alter: "أدخل اسم المنتج بدقة..."),
                englishPlaceholder: Language.get("EnterItemNameEn", alter: "Enter item name in English..."),
                selectedLanguage: $bilingualLanguage,
                isFocused: focusedField == .name,
                onFocusChange: { focused in
                    if focused { focusedField = .name }
                    else if focusedField == .name { focusedField = nil }
                },
                onSubmit: { focusedField = .desc }
            )
            .id(FormField.name)

            PPBilingualTextEditorField(
                title: Language.get("Description", alter: "الوصف التفصيلي والمواصفات"),
                isRequired: false,
                arabicText: $viewModel.desc,
                englishText: $viewModel.descEn,
                arabicPlaceholder: Language.get("DescriptionPlaceholder", alter: "أدخل وصف المنتج ومواصفاته بالتفصيل..."),
                englishPlaceholder: Language.get("DescriptionPlaceholderEn", alter: "Enter detailed item description and specs..."),
                selectedLanguage: $bilingualLanguage,
                minHeight: 88,
                isFocused: focusedField == .desc,
                onFocusChange: { focused in
                    if focused { focusedField = .desc }
                    else if focusedField == .desc { focusedField = nil }
                }
            )
            .id(FormField.desc)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private var taxonomyClassificationDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Language.get("Taxonomy", alter: "التصنيف والنوع والسلالة"), systemImage: "circle.grid.cross.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                // Species Selector Card
                Button {
                    focusedField = nil
                    viewModel.showSpeciesPicker = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Species", alter: "نوع الحيوان (الفئة)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                            Text(viewModel.selectedCategoryDisplayTitle ?? Language.get("SelectSpecies", alter: "اختر النوع..."))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(viewModel.selectedCategoryDisplayTitle != nil ? AdminSurface.primaryText : AdminCommandInk.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(EditorPressStyle())

                // Breed Selector Card
                Button {
                    if viewModel.selectedMainKind != nil {
                        focusedField = nil
                        viewModel.showBreedPicker = true
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Breed", alter: "السلالة الفرعية"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                            Text(viewModel.selectedSubKind?.subKindName ?? Language.get("SelectBreed", alter: "اختياري..."))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(viewModel.selectedSubKind != nil ? AdminSurface.primaryText : AdminCommandInk.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(viewModel.selectedMainKind != nil ? AdminSurface.primary : AdminCommandInk.tertiary)
                    }
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(EditorPressStyle())
                .disabled(viewModel.selectedMainKind == nil)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - 6. STAGE 2: Biometric & Health Registry Canvas

    private var bioVaultStageCanvas: some View {
        VStack(spacing: 16) {
            if viewModel.isLivePet {
                // Tracking Mode Segmented Bar
                liveInventoryTrackingModeDeck

                // Unit Flight Deck (Individual) OR Batch Intake Deck (Quantity)
                if viewModel.liveInventoryMode == .individual && !viewModel.isEditingLivePet {
                    liveUnitFlightDeck
                } else if viewModel.liveInventoryMode == .quantity {
                    liveQuantityIntakeDeck
                }

                // Gender Triad
                genderTriadDeck

                // Biometric Certification Shields
                biometricHealthShieldsDeck
            } else {
                // Non-live product specifications
                nonLiveProductSpecsDeck
            }
        }
    }

    private var liveInventoryTrackingModeDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("LivePet_Tracking_Title", alter: "نمط إدارة وتتبع المخزون الحي"), systemImage: "tag.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            Picker(Language.get("LivePet_Tracking_Title", alter: "نمط إدارة المخزون الحي"), selection: $viewModel.liveInventoryMode) {
                ForEach(PPLivePetInventoryMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isEditingLivePet)
            .onChange(of: viewModel.liveInventoryMode) { mode in
                viewModel.selectLiveInventoryMode(mode)
            }

            Text(viewModel.liveInventoryMode.localizedHint)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isEditingLivePet {
                Label(
                    Language.get("LivePet_Tracking_Locked_Hint", alter: "نمط التتبع ثابت بعد الإنشاء. استخدم مساحة عمليات الحيوانات لإدارة الحالات الفردية."),
                    systemImage: "lock.shield"
                )
                .font(AdminType.caption2)
                .foregroundStyle(Color(uiColor: .ppWarning))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // Individual Unit Flight Pods with Smart Clone
    private var liveUnitFlightDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("UnitsFlightDeck", alter: "سجلات الحيوانات الفردية"), systemImage: "number.circle.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text(verbatim: "\(viewModel.livePetUnits.count.englishDigits)/100 " + Language.get("Units", alter: "حيوان"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(uiColor: .ppSuccess))
            }

            VStack(spacing: 12) {
                ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { index, unit in
                    let binding = $viewModel.livePetUnits[index]
                    unitFlightPodCard(index: index, unit: unit, binding: binding)
                }

                // Add Unit Button
                Button {
                    viewModel.addLivePetUnit()
                } label: {
                    Label(Language.get("LivePet_Add_Another_Unit", alter: "إضافة حيوان آخر للسجل"), systemImage: "plus.circle.fill")
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4]))
                                .foregroundStyle(AdminSurface.primary.opacity(0.4))
                        )
                }
                .buttonStyle(EditorPressStyle())
                .disabled(viewModel.livePetUnits.count >= 100)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 0.75)
        )
    }

    private func unitFlightPodCard(index: Int, unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Unit Number Badge
                HStack(spacing: 4) {
                    Text(verbatim: "#\((index + 1).englishDigits)")
                        .font(PPBrandFont.bold(size: 13))
                    Text(Language.get("AnimalUnit", alter: "حيوان"))
                        .font(AdminType.caption2)
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())

                Spacer()

                // Smart Clone Action
                Button {
                    viewModel.clonePreviousUnit(from: unit)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 11))
                        Text(Language.get("SmartClone", alter: "تكرار ذكي"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundColor(Color(uiColor: .ppSuccess))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                // Remove Action (if more than 1 unit)
                if viewModel.livePetUnits.count > 1 {
                    Button(role: .destructive) {
                        viewModel.removeLivePetUnit(id: unit.id)
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.red.opacity(0.8))
                    }
                    .padding(4)
                }
            }

            // Monospace Ring Tag Input
            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("LivePet_Ring_Placeholder", alter: "رقم الحلقة أو الشريحة التعريفية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 8) {
                    TextField("QA-RING-000", text: binding.ringTag)
                        .font(PPBrandFont.bold(size: 15))
                        .textInputAutocapitalization(.characters)
                        .environment(\.layoutDirection, .leftToRight)

                    if !binding.ringTag.wrappedValue.isEmpty {
                        Button {
                            binding.ringTag.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }

                    AdminBarcodeScanButton { scanned in
                        binding.ringTag.wrappedValue = scanned
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Inline Price and Cost
            HStack(spacing: 10) {
                livePetUnitNumberField(
                    title: Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع (ر.ق)"),
                    text: binding.sellingPriceText
                )
                if viewModel.canViewStockCosts {
                    livePetUnitNumberField(
                        title: Language.get("LivePet_Unit_PurchaseCost", alter: "تكلفة الشراء (ر.ق)"),
                        text: binding.purchaseCostText
                    )
                }
            }

            // Acquisition Date Picker
            DatePicker(
                Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"),
                selection: binding.acquisitionDate,
                displayedComponents: .date
            )
            .font(AdminType.caption1)

            // Supplier and Notes
            TextField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد أو المصدر (اختياري)"), text: binding.supplier)
                .font(AdminType.callout)
                .padding(10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField(Language.get("LivePet_Unit_Notes_Placeholder", alter: "ملاحظات داخلية خاصة بالسجل (اختياري)"), text: binding.notes)
                .font(AdminType.callout)
                .padding(10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var liveQuantityIntakeDeck: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if viewModel.canViewStockCosts {
                    livePetUnitNumberField(
                        title: Language.get("LivePet_Group_PurchaseCost", alter: "تكلفة الوحدة الواحدة"),
                        text: $viewModel.liveGroupCostText
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    DatePicker("", selection: $viewModel.liveArrivalDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            TextField(Language.get("LivePet_Supplier_Placeholder", alter: "اسم المورد، اختياري"), text: $viewModel.liveSupplier)
                .font(AdminType.callout)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField(Language.get("LivePet_Group_Notes_Placeholder", alter: "ملاحظات إدخال المجموعة، اختيارية"), text: $viewModel.liveIntakeNotes)
                .font(AdminType.callout)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // Gender Triad with Chromatic Lighting
    private var genderTriadDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Gender", alter: "التصنيف البيولوجي والجنس"), systemImage: "figure.2.arms.open")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 10) {
                genderTriadPill(id: "male", title: "ذكر ♂", baseColor: Color.blue)
                genderTriadPill(id: "female", title: "أنثى ♀", baseColor: Color.pink)
                genderTriadPill(id: "pair", title: "زوج ⚥", baseColor: Color.purple)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private func genderTriadPill(id: String, title: String, baseColor: Color) -> some View {
        let isSelected = viewModel.selectedGender == id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.selectedGender = id
            }
        } label: {
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected
                        ? AnyView(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(baseColor)
                                .shadow(color: baseColor.opacity(0.35), radius: 8, x: 0, y: 3)
                        )
                        : AnyView(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AdminSurface.control)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // Biometric Certification Shields
    private var biometricHealthShieldsDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("BiometricHealthShields", alter: "الجواز الصحي وشهادات السلامة البيطرية"), systemImage: "shield.lefthalf.filled")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 10) {
                // Vaccination Shield
                biometricShieldCard(
                    title: Language.get("FullyVaccinated", alter: "ملقح بالكامل ومحصن بيطرياً"),
                    subtitle: Language.get("VaccinatedSub", alter: "شهادة تحصين سارية وخالي من الأمراض المعدية"),
                    icon: "cross.case.fill",
                    accentColor: Color(uiColor: .ppSuccess),
                    isOn: $viewModel.isVaccinated
                )

                // Deworming Shield
                biometricShieldCard(
                    title: Language.get("Dewormed", alter: "معالج وقائياً ضد الطفيليات والديدان"),
                    subtitle: Language.get("DewormedSub", alter: "جرعة وقائية دورية مسجلة في السجل الصحي"),
                    icon: "shield.checkered",
                    accentColor: Color(uiColor: .ppSuccess),
                    isOn: $viewModel.isDewormed
                )

                // International Microchip Shield
                biometricShieldCard(
                    title: Language.get("Microchipped", alter: "شريحة تعريف إلكترونية دولية (RFID)"),
                    subtitle: Language.get("MicrochippedSub", alter: "شريحة مزروعة متوافقة مع المعايير الدولية ISO"),
                    icon: "cpu.fill",
                    accentColor: Color.blue,
                    isOn: $viewModel.isMicrochipped
                )
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.75)
        )
    }

    private func biometricShieldCard(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOn.wrappedValue ? accentColor.opacity(0.16) : AdminSurface.control)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isOn.wrappedValue ? accentColor : AdminCommandInk.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AdminSurface.primary)
        }
        .padding(12)
        .background(AdminSurface.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Non-Live Product Specifications (Accessories & Food)
    private var nonLiveProductSpecsDeck: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(Language.get("ProductSpecs", alter: "المواصفات وحالة العنصر"), systemImage: "slider.horizontal.3")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            PPAccessoryConditionSelector(
                condition: $viewModel.condition,
                isFood: viewModel.isFood
            )

            if viewModel.isFood {
                PPAccessoryUnifiedMeasureChamber(
                    weightText: $viewModel.weightText,
                    weightUnit: $viewModel.weightUnit,
                    onFocusChanged: { focused in
                        if focused { focusedField = .weight }
                        else if focusedField == .weight { focusedField = nil }
                    }
                )

                PPAccessoryExpirySentinel(
                    hasExpiryDate: $viewModel.hasExpiryDate,
                    expiryDate: $viewModel.expiryDate
                )
            } else {
                PPPhysicalSpecOrchestrator(
                    viewModel: viewModel,
                    onFocusChanged: { focused in
                        if focused { focusedField = .weight }
                        else if focusedField == .weight { focusedField = nil }
                    }
                )
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - 7. STAGE 3: Pricing & Profit Engine Canvas

    private var pricingStageCanvas: some View {
        VStack(spacing: 16) {
            // Financial Pricing Deck
            financialPricingDeck

            // Selling Units Deck (Accessories & Food only)
            if !viewModel.isIndividualLivePet {
                sellingUnitsDeck
            }

            // Profit & Margin Telemetry (if permitted)
            if let telemetry = viewModel.profitMarginTelemetry {
                profitMarginTelemetryDeck(margin: telemetry.marginPercent, profit: telemetry.netProfit)
            }

            // Stock Inventory Stepper (for batch or regular items)
            if !viewModel.isIndividualLivePet {
                stockQuantityStepperDeck
            }
        }
    }

    private var financialPricingDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                viewModel.isIndividualLivePet
                    ? Language.get("LivePet_Standard_SellingPrice", alter: "سعر البيع القياسي")
                    : Language.get("PricingAndDiscounts", alter: "التسعير والعروض الترويجية"),
                systemImage: "tag.circle.fill"
            )
            .font(AdminType.headline)
            .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                // Base Price
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(
                            viewModel.isIndividualLivePet
                                ? Language.get("LivePet_Standard_SellingPrice_QAR", alter: "السعر القياسي (ر.ق)")
                                : Language.get("BasePrice", alter: "السعر الأساسي (ر.ق)")
                        )
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showPricePad = true
                        } label: {
                            Image(systemName: "circle.grid.3x3.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    TextField("0.00", text: $viewModel.priceText)
                        .font(PPBrandFont.bold(size: 18))
                        .englishNumericInput(text: $viewModel.priceText, allowsDecimal: true)
                        .focused($focusedField, equals: .price)
                        .padding(14)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !viewModel.isIndividualLivePet {
                    // Discount Percent
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Language.get("DiscountPercent", alter: "نسبة الخصم (%)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)

                            Spacer()

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showDiscountPad = true
                            } label: {
                                Image(systemName: "circle.grid.3x3.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }

                        TextField("0", text: $viewModel.discountPercentText)
                            .font(PPBrandFont.bold(size: 18))
                            .englishNumericInput(text: $viewModel.discountPercentText, allowsDecimal: true)
                            .focused($focusedField, equals: .discountPercent)
                            .padding(14)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            if viewModel.isIndividualLivePet {
                Label(
                    Language.get("LivePet_Standard_SellingPrice_Hint", alter: "يُستخدم هذا السعر كقيمة افتراضية للحيوانات الجديدة؛ وسعر كل سجل فردي هو المرجع النهائي لنقطة البيع."),
                    systemImage: "info.circle.fill"
                )
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            customerFinalPricePlate

            if !viewModel.isIndividualLivePet {
                Divider().opacity(0.4)
                wholesalePricingSection
                livePricingSummaryPlate
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private var customerFinalPricePlate: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("FinalCustomerPrice", alter: "السعر النهائي في التطبيق للعميل"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(verbatim: viewModel.formattedFinalPrice.normalizedEnglishDigits)
                    .font(AdminType.title2)
                    .foregroundStyle(AdminSurface.primary)
            }
            Spacer()
            if viewModel.calculatedFinalPrice < viewModel.basePrice && viewModel.basePrice > 0 {
                Text(verbatim: String(format: Language.get("DiscountSavings", alter: "خصم %.0f ر.ق"), viewModel.basePrice - viewModel.calculatedFinalPrice).normalizedEnglishDigits)
                    .font(AdminType.captionBold)
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule(style: .continuous))
            }
        }
        .padding(14)
        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var wholesalePricingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $viewModel.wholesaleEnabled.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .systemTeal).opacity(viewModel.wholesaleEnabled ? 0.18 : 0.08))
                            .frame(width: 34, height: 34)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal) : AdminCommandInk.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Wholesale_Selling_Title", alter: "البيع بالجملة (Wholesale)"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(viewModel.wholesaleEnabled
                            ? Language.get("Wholesale_Active_Hint", alter: "مفعل ومتاح في نقطة البيع للموزعين والعملاء بالجملة")
                            : Language.get("Wholesale_Inactive_Hint", alter: "غير مفعل (قم بالتشغيل لتحديد سعر الجملة)"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }
            .tint(Color(uiColor: .systemTeal))

            if viewModel.wholesaleEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Wholesale_Price_QAR", alter: "سعر بيع الجملة للوحدة الافتراضية (ر.ق)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .systemTeal))

                    TextField("0.00", text: $viewModel.wholesalePriceText)
                        .font(PPBrandFont.bold(size: 18))
                        .englishNumericInput(text: $viewModel.wholesalePriceText, allowsDecimal: true)
                        .focused($focusedField, equals: .wholesalePrice)
                        .padding(14)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal).opacity(0.35) : Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 1)
        )
    }

    private var livePricingSummaryPlate: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Summary_Retail_Label", alter: "التجزئة"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(verbatim: viewModel.defaultRetailGroupSummary.normalizedEnglishDigits)
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            if let wholesaleSummary = viewModel.defaultWholesaleGroupSummary {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Summary_Wholesale_Label", alter: "الجملة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .systemTeal))
                    Text(verbatim: wholesaleSummary.normalizedEnglishDigits)
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(Color(uiColor: .systemTeal))
                }
            }
        }
        .padding(12)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sellingUnitsDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(Language.get("Selling_Units_Deck_Title", alter: "وحدات ومجموعات البيع"), systemImage: "square.stack.3d.up.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Button {
                    let nextSort = viewModel.quantityGroups.count
                    let newGroup = PPQuantityGroupDraft(
                        id: "pack_\(nextSort + 1)_\(UUID().uuidString.prefix(4))",
                        nameAr: "",
                        nameEn: "",
                        unitsPerGroup: 6,
                        barcode: "",
                        sku: "",
                        sortOrder: nextSort,
                        retailEnabled: true,
                        wholesaleEnabled: viewModel.wholesaleEnabled,
                        retailPriceText: "",
                        wholesalePriceText: "",
                        defaultForRetail: false,
                        defaultForWholesale: false,
                        active: true
                    )
                    viewModel.selectedQuantityGroupForEditing = newGroup
                    viewModel.showQuantityGroupInspector = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(Language.get("Add_Selling_Unit", alter: "إضافة وحدة"))
                    }
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }

            Text(Language.get("Selling_Units_Deck_Subtitle", alter: "تحديد أحجام البيع (حبة، شدة، كرتون) مع خصم المخزون التلقائي بالوحدات الأساسية."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)

            VStack(spacing: 10) {
                ForEach(viewModel.quantityGroups) { group in
                    sellingUnitRow(for: group)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private func sellingUnitRow(for group: PPQuantityGroupDraft) -> some View {
        Button {
            viewModel.selectedQuantityGroupForEditing = group
            viewModel.showQuantityGroupInspector = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(group.defaultForRetail ? AdminSurface.primary.opacity(0.15) : AdminSurface.control)
                        .frame(width: 40, height: 40)
                    Image(systemName: group.unitsPerGroup == 1 ? "cube.fill" : "shippingbox.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(group.defaultForRetail ? AdminSurface.primary : AdminCommandInk.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.localizedName)
                            .font(AdminType.bodyBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        if group.defaultForRetail {
                            Text(Language.get("Default_Retail_Badge", alter: "افتراضي للتجزئة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                        if group.defaultForWholesale && group.wholesaleEnabled {
                            Text(Language.get("Default_Wholesale_Badge", alter: "افتراضي للجملة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(uiColor: .systemTeal))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemTeal).opacity(0.12), in: Capsule())
                        }
                    }
                    Text(verbatim: group.unitsCountText.normalizedEnglishDigits)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if group.retailEnabled {
                        Text(verbatim: String(format: "%.0f %@", group.retailPrice, Language.get("QAR", alter: "ر.ق")).normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    if group.wholesaleEnabled {
                        Text(verbatim: String(format: Language.get("Wholesale_Price_Format", alter: "جملة: %.0f ر.ق"), group.wholesalePrice).normalizedEnglishDigits)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(uiColor: .systemTeal))
                    }
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.secondary.opacity(0.6))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func profitMarginTelemetryDeck(margin: Double, profit: Double) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .ppSuccess).opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppSuccess))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("MarginTelemetry", alter: "مؤشر الربحية والهامش التجاري"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                HStack(spacing: 8) {
                    Text(verbatim: String(format: "%.1f%%", margin).normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: 20))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                    Text(verbatim: String(format: "+%.0f %@", profit, Language.get("QAR", alter: "ر.ق")).normalizedEnglishDigits)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 1)
        )
    }

    private var stockQuantityStepperDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("StockQuantity", alter: "الكمية المتوفرة بالمخزن"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)

            HStack(spacing: 12) {
                Button {
                    if viewModel.quantity > 1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.quantity -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.quantity <= 1)

                Text(verbatim: viewModel.quantity.englishDigits)
                    .font(PPBrandFont.bold(size: 22))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        quantityAlertText = viewModel.quantity.englishDigits
                        showQuantityAlert = true
                    }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.quantity += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(6)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.6)))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - 8. STAGE 4: Store Allocation & Governance Canvas

    private var governanceStageCanvas: some View {
        VStack(spacing: 16) {
            // Store Allocation Card
            Button {
                focusedField = nil
                viewModel.showStorePicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("StoreBranch", alter: "الفرع / المتجر المالك"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Text(viewModel.selectedStoreName)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(16)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
                )
            }
            .buttonStyle(EditorPressStyle())

            // Publishing Status Card (Draft vs Active)
            VStack(spacing: 8) {
                Toggle(isOn: $viewModel.isDraft) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("SaveAsDraft", alter: "حفظ كمسودة مخفية مؤقتاً"))
                            .font(AdminType.headline)
                        Text(Language.get("DraftDesc", alter: "لن يظهر المنتج للعملاء في التطبيق حتى يتم تفعيله واعتماده."))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                .tint(Color(uiColor: .ppWarning))
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
    }

    // MARK: - 9. Tactical Floating Save Dock

    private var tacticalSaveDock: some View {
        VStack(spacing: 6) {
            // Real-Time Requirement Radar Banner
            if let hint = viewModel.missingRequirementHint {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                    Text(hint)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.saveAccessory()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 17, weight: .bold))
                            Text(Language.get("SaveAndPublish", alter: "حفظ واعتماد الصنف"))
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
                .buttonStyle(EditorPressStyle())
                .disabled(viewModel.isSubmitting)
            }
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

    private func livePetUnitNumberField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            TextField("0.00", text: text)
                .font(PPBrandFont.bold(size: 15))
                .englishNumericInput(text: text, allowsDecimal: true)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Press Style

private struct EditorPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Flagship Modal Pickers

// MARK: - Flagship Modal Pickers: Sovereign Unit of Sale Architecture (NextGen V6)

// MARK: - Smart Packaging Archetype Model

private struct PPUnitArchetype: Identifiable, Hashable {
    let id: String
    let icon: String
    let nameAr: String
    let nameEn: String
    let defaultMultiplier: Int
    let badgeKey: String
    let badgeFallback: String

    static let allArchetypes: [PPUnitArchetype] = [
        PPUnitArchetype(id: "single", icon: "cube.fill", nameAr: "حبة", nameEn: "Single", defaultMultiplier: 1, badgeKey: "Unit_Single_Base", badgeFallback: "قطعة مفردة"),
        PPUnitArchetype(id: "pack6", icon: "shippingbox.fill", nameAr: "ربطة", nameEn: "Pack", defaultMultiplier: 6, badgeKey: "Unit_Pack_6", badgeFallback: "ربطة / باقة"),
        PPUnitArchetype(id: "halfDozen", icon: "square.grid.2x2.fill", nameAr: "نصف درزن", nameEn: "Half Dozen", defaultMultiplier: 6, badgeKey: "Unit_Half_Dozen", badgeFallback: "نصف درزن"),
        PPUnitArchetype(id: "dozen", icon: "square.grid.3x2.fill", nameAr: "درزن", nameEn: "Dozen", defaultMultiplier: 12, badgeKey: "Unit_Full_Dozen", badgeFallback: "درزن كامل"),
        PPUnitArchetype(id: "carton", icon: "archivebox.fill", nameAr: "كرتون", nameEn: "Carton", defaultMultiplier: 24, badgeKey: "Unit_Carton_24", badgeFallback: "كرتون تجاري"),
        PPUnitArchetype(id: "box10", icon: "tray.2.fill", nameAr: "صندوق", nameEn: "Box", defaultMultiplier: 10, badgeKey: "Unit_Box_10", badgeFallback: "صندوق / كيس"),
        PPUnitArchetype(id: "kg", icon: "scalemass.fill", nameAr: "كيلو", nameEn: "Kg", defaultMultiplier: 1, badgeKey: "Unit_Kilogram", badgeFallback: "كيلوجرام")
    ]
}

// MARK: - Unit Economics Analysis Helper

private struct PPUnitEconomicsHelper {
    let retailPrice: Double
    let wholesalePrice: Double
    let unitsPerGroup: Int

    var pricePerPiece: Double? {
        guard retailPrice > 0, unitsPerGroup > 0 else { return nil }
        return retailPrice / Double(unitsPerGroup)
    }

    var wholesalePricePerPiece: Double? {
        guard wholesalePrice > 0, unitsPerGroup > 0 else { return nil }
        return wholesalePrice / Double(unitsPerGroup)
    }

    var wholesaleSavingsPercent: Double? {
        guard retailPrice > 0, wholesalePrice > 0, wholesalePrice < retailPrice else { return nil }
        return ((retailPrice - wholesalePrice) / retailPrice) * 100.0
    }

    var wholesaleSavingsAmount: Double? {
        guard retailPrice > 0, wholesalePrice > 0, wholesalePrice < retailPrice else { return nil }
        return retailPrice - wholesalePrice
    }

    var isWholesaleMoreExpensive: Bool {
        retailPrice > 0 && wholesalePrice > retailPrice
    }
}

// MARK: - Dynamic 3D Isometric Unit Packaging Sigil

private struct PPIsometricPackageSigil: View {
    let unitsCount: Int
    let isCompact: Bool
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // Ambient Aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AdminSurface.primary.opacity(0.18),
                            AdminSurface.primary.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: isCompact ? 44 : 70
                    )
                )
                .frame(width: isCompact ? 76 : 124, height: isCompact ? 76 : 124)
                .scaleEffect(isPulsing ? 1.06 : 0.94)

            // Dynamic Box Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: isCompact ? 16 : 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AdminSurface.surface,
                                AdminSurface.control.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: isCompact ? 16 : 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        AdminSurface.primary.opacity(0.40),
                                        AdminSurface.borderSubtle
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.25
                            )
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)

                VStack(spacing: isCompact ? 2 : 4) {
                    Image(systemName: iconNameForCount(unitsCount))
                        .font(.system(size: isCompact ? 22 : 34, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text(verbatim: "\(unitsCount)x")
                        .font(Font.custom("Beiruti-Bold", size: isCompact ? 13 : 16))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .frame(width: isCompact ? 62 : 92, height: isCompact ? 62 : 92)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func iconNameForCount(_ count: Int) -> String {
        if count <= 1 { return "cube.fill" }
        if count <= 6 { return "shippingbox.fill" }
        if count <= 12 { return "square.grid.3x2.fill" }
        return "archivebox.fill"
    }
}

// MARK: - Main Sovereign Unit Inspector Sheet

struct PPQuantityGroupInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var group: PPQuantityGroupDraft
    let canManageWholesale: Bool
    let onSave: (PPQuantityGroupDraft) -> Void
    let onDelete: (() -> Void)?

    @State private var unitsText: String = "1"
    @State private var localErrorMessage: String? = nil
    @State private var showDeleteConfirmation: Bool = false

    init(
        group: PPQuantityGroupDraft,
        canManageWholesale: Bool,
        onSave: @escaping (PPQuantityGroupDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _group = State(initialValue: group)
        _unitsText = State(initialValue: "\(max(1, group.unitsPerGroup))")
        self.canManageWholesale = canManageWholesale
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var economics: PPUnitEconomicsHelper {
        PPUnitEconomicsHelper(
            retailPrice: group.retailPrice,
            wholesalePrice: group.wholesalePrice,
            unitsPerGroup: group.unitsPerGroup
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let isIPad = horizontalSizeClass == .regular || proxy.size.width >= 760

            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()

                if isIPad {
                    iPadQuantityGroupInspector(
                        group: $group,
                        unitsText: $unitsText,
                        canManageWholesale: canManageWholesale,
                        economics: economics,
                        localErrorMessage: localErrorMessage,
                        onSave: validateAndSave,
                        onCancel: { dismiss() },
                        onDelete: onDelete != nil ? { showDeleteConfirmation = true } : nil
                    )
                } else {
                    iPhoneQuantityGroupInspector(
                        group: $group,
                        unitsText: $unitsText,
                        canManageWholesale: canManageWholesale,
                        economics: economics,
                        localErrorMessage: localErrorMessage,
                        onSave: validateAndSave,
                        onCancel: { dismiss() },
                        onDelete: onDelete != nil ? { showDeleteConfirmation = true } : nil
                    )
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .alert(
            Language.get("Delete_Unit_Confirm_Title", alter: "هل أنت متأكد من حذف وحدة البيع هذه؟"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(Language.get("Delete_Selling_Unit", alter: "حذف وحدة البيع هذه"), role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
        } message: {
            Text(Language.get("Delete_Unit_Confirm_Msg", alter: "سيتم إلغاء هذه الوحدة من قائمة وحدات البيع لهذا الصنف ولن تتوفر في الكاشير."))
        }
    }

    private func validateAndSave() {
        if let parsed = Int(unitsText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            group.unitsPerGroup = parsed
        }
        if group.unitsPerGroup < 1 {
            withAnimation(.spring(response: 0.35)) {
                localErrorMessage = Language.get("Validation_Group_Units_Positive", alter: "يجب أن تكون كمية المجموعة عدداً صحيحاً أكبر من صفر.")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        if !group.retailEnabled && !group.wholesaleEnabled {
            withAnimation(.spring(response: 0.35)) {
                localErrorMessage = Language.get("Validation_Channel_Required", alter: "يرجى تفعيل قناة بيع واحدة على الأقل (تجزئة أو جملة).")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        if group.retailEnabled && group.retailPrice <= 0 {
            withAnimation(.spring(response: 0.35)) {
                localErrorMessage = Language.get("Validation_Retail_Price_Required", alter: "يرجى تحديد سعر بيع التجزئة بدقة.")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        if group.wholesaleEnabled && group.wholesalePrice <= 0 {
            withAnimation(.spring(response: 0.35)) {
                localErrorMessage = Language.get("Validation_Wholesale_Price_Required", alter: "يرجى تحديد سعر بيع الجملة بدقة.")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        localErrorMessage = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave(group)
        dismiss()
    }
}

// MARK: - iPhone Tactical Quantity Group Inspector

private struct iPhoneQuantityGroupInspector: View {
    @Binding var group: PPQuantityGroupDraft
    @Binding var unitsText: String
    let canManageWholesale: Bool
    let economics: PPUnitEconomicsHelper
    let localErrorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Sticky Navigation Header
            navigationHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    AdminSurface.surface
                        .ignoresSafeArea(edges: .top)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                )

            // Scrollable Content Runway
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Live Unit Summary Pill Deck
                    liveUnitSummaryPill

                    // 2. Smart Packaging Archetypes Carousel
                    archetypesCarouselSection

                    // 3. Bilingual Nomenclature Card
                    identityBilingualCard

                    // 4. Physical Multiplier & Packaging Matrix
                    packagingMultiplierCard

                    // 5. Barcode & SKU Identifiers Studio
                    identifiersStudioCard

                    // 6. Live Economics & Pricing Breakdown Radar
                    if economics.pricePerPiece != nil {
                        economicsRadarCard
                    }

                    // 7. Retail Sales Channel Card
                    retailChannelCard

                    // 8. Wholesale Sales Channel Card (if allowed)
                    if canManageWholesale {
                        wholesaleChannelCard
                    }

                    // 9. Point of Sale (POS) Operational Beacon
                    posMasterBeaconCard

                    // 10. Destructive Action (if allowed)
                    if let onDelete = onDelete {
                        Button(role: .destructive, action: onDelete) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(Language.get("Delete_Selling_Unit", alter: "حذف وحدة البيع هذه"))
                                    .font(AdminType.subheadlineBold)
                            }
                            .foregroundStyle(Color(uiColor: .systemRed))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(uiColor: .systemRed).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color(uiColor: .systemRed).opacity(0.25), lineWidth: 1)
                            )
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 90)
                }
                .padding(16)
            }

            // Floating Tactile Save Dock
            tactileSaveDock
        }
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        HStack {
            Button(Language.get("Cancel", alter: "إلغاء"), action: onCancel)
                .font(AdminType.body)
                .foregroundStyle(AdminCommandInk.secondary)

            Spacer()

            VStack(spacing: 2) {
                Text(Language.get("Edit_Selling_Unit", alter: "وحدة البيع"))
                    .font(Font.custom("Beiruti-Bold", size: 20))
                    .foregroundStyle(AdminSurface.primaryText)

                if !group.localizedName.isEmpty {
                    Text(group.localizedName)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.primary)
                }
            }

            Spacer()

            Button(action: onSave) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Done", alter: "تم"))
                        .font(AdminType.calloutBold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(EditorPressStyle())
        }
    }

    // MARK: - 1. Live Unit Summary Pill Deck

    private var liveUnitSummaryPill: some View {
        HStack(spacing: 12) {
            PPIsometricPackageSigil(unitsCount: group.unitsPerGroup, isCompact: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.localizedName.isEmpty ? Language.get("Edit_Selling_Unit", alter: "وحدة البيع") : group.localizedName)
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(
                        group.unitsPerGroup == 1
                            ? Language.get("Unit_Single_Base", alter: "قطعة مفردة")
                            : String(format: Language.get("Unit_Multiple_Pieces_Format", alter: "%@ قطع"), group.unitsPerGroup.englishDigits),
                        systemImage: "equal.circle.fill"
                    )
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)

                    if group.retailEnabled && group.retailPrice > 0 {
                        Text("•")
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(verbatim: "\(group.retailPriceText) ر.ق")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }
                }
            }

            Spacer()

            // Status Badges
            VStack(alignment: .trailing, spacing: 4) {
                if group.active {
                    Text(verbatim: "POS")
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }
                if group.defaultForRetail {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                        Text(Language.get("Default", alter: "افتراضي"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 217/255, green: 119/255, blue: 6/255))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 251/255, green: 191/255, blue: 36/255).opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 2. Smart Packaging Archetypes Carousel

    private var archetypesCarouselSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Language.get("Unit_Archetypes_Title", alter: "أنماط التعبئة والتغليف السريعة"), systemImage: "sparkles")
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PPUnitArchetype.allArchetypes) { archetype in
                        let isSelected = group.unitsPerGroup == archetype.defaultMultiplier &&
                            (group.nameAr == archetype.nameAr || group.nameEn == archetype.nameEn)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                group.nameAr = archetype.nameAr
                                group.nameEn = archetype.nameEn
                                group.unitsPerGroup = archetype.defaultMultiplier
                                unitsText = archetype.defaultMultiplier.englishDigits
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: archetype.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Language.isRTL() ? archetype.nameAr : archetype.nameEn)
                                        .font(AdminType.captionBold)
                                        .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)

                                    Text(verbatim: "\(archetype.defaultMultiplier)x")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : AdminCommandInk.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? LinearGradient(
                                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [AdminSurface.surface, AdminSurface.surface],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : AdminSurface.borderSubtle, lineWidth: 1)
                            )
                            .shadow(color: isSelected ? AdminSurface.primary.opacity(0.25) : Color.black.opacity(0.02), radius: 4, y: 1)
                        }
                        .buttonStyle(EditorPressStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 3. Bilingual Nomenclature Card

    private var identityBilingualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Group_Identity", alter: "اسم ومواصفات وحدة البيع"), systemImage: "pencil.line")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Group_Name_Ar", alter: "اسم الوحدة (عربي)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    TextField(Language.get("e.g. Carton", alter: "مثال: كرتون"), text: $group.nameAr)
                        .font(AdminType.body)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .forceKeyboardLanguage(.arabic)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Group_Name_En", alter: "اسم الوحدة (إنجليزي)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    TextField("e.g. Carton", text: $group.nameEn)
                        .font(AdminType.body)
                        .environment(\.layoutDirection, .leftToRight)
                        .multilineTextAlignment(.leading)
                        .keyboardType(.asciiCapable)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .forceKeyboardLanguage(.english)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 4. Physical Multiplier & Packaging Matrix

    private var packagingMultiplierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Units_Per_Group_Count", alter: "عدد الحبات في هذه الوحدة (القطع الأساسية)"), systemImage: "square.grid.3x3.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(verbatim: "\(group.unitsPerGroup)x")
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminSurface.primary)
            }

            // Tactile Physical Stepper Row
            HStack(spacing: 12) {
                Button {
                    let current = Int(unitsText) ?? 1
                    if current > 1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        unitsText = (current - 1).englishDigits
                        group.unitsPerGroup = current - 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .buttonStyle(EditorPressStyle())

                TextField("1", text: $unitsText)
                    .font(PPBrandFont.bold(size: 24))
                    .multilineTextAlignment(.center)
                    .englishNumericInput(text: $unitsText, allowsDecimal: false)
                    .padding(10)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: unitsText) { newVal in
                        if let parsed = Int(newVal), parsed >= 1 {
                            group.unitsPerGroup = parsed
                        }
                    }

                Button {
                    let current = Int(unitsText) ?? 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    unitsText = (current + 1).englishDigits
                    group.unitsPerGroup = current + 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .buttonStyle(EditorPressStyle())
            }

            // Quick Jump Multiplier Pills
            HStack(spacing: 8) {
                ForEach(Self.jumpMultipliers, id: \.self) { count in
                    multiplierJumpPill(for: count)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    private static let jumpMultipliers: [Int] = [1, 6, 12, 24, 50, 100]

    @ViewBuilder
    private func multiplierJumpPill(for count: Int) -> some View {
        let isCurrent = group.unitsPerGroup == count
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3)) {
                group.unitsPerGroup = count
                unitsText = count.englishDigits
            }
        } label: {
            Text(verbatim: "\(count)")
                .font(AdminType.captionBold)
                .foregroundStyle(isCurrent ? Color.white : AdminCommandInk.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? AdminSurface.primary : AdminSurface.control)
                )
        }
        .buttonStyle(EditorPressStyle())
    }

    // MARK: - 5. Barcode & SKU Identifiers Studio

    private var identifiersStudioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Identifiers", alter: "بيانات التعريف والباركود"), systemImage: "barcode.viewfinder")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            // Barcode Field with Integrated Camera Scanner
            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Group_Barcode", alter: "باركود المجموعة (اختياري)"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .foregroundStyle(AdminCommandInk.secondary)

                    TextField(Language.get("Barcode", alter: "امسح أو اكتب الباركود"), text: $group.barcode)
                        .font(AdminType.body.monospaced())
                        .englishNumericInput(text: $group.barcode, allowsDecimal: false)

                    if !group.barcode.isEmpty {
                        Button {
                            UIPasteboard.general.string = group.barcode
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }

                        Button {
                            group.barcode = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                    }

                    // Live Camera Scanner Button
                    AdminBarcodeScanButton { scannedCode in
                        group.barcode = scannedCode
                    }
                }
                .padding(10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // SKU Field with Quick Auto-Generator
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.get("Group_SKU", alter: "رمز الصنف SKU (اختياري)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    Spacer()

                    if group.sku.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            let prefix = group.nameEn.filter { $0.isLetter }.prefix(4).uppercased()
                            let tag = prefix.isEmpty ? "UNIT" : String(prefix)
                            group.sku = "\(tag)-\(group.unitsPerGroup)X-\(Int.random(in: 100...999))"
                        } label: {
                            Label(Language.get("Generate_SKU_Auto", alter: "توليد SKU"), systemImage: "wand.and.stars")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }

                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(AdminCommandInk.secondary)

                    TextField("SKU", text: $group.sku)
                        .font(AdminType.body.monospaced())
                        .keyboardType(.asciiCapable)
                        .forceKeyboardLanguage(.english)

                    if !group.sku.isEmpty {
                        Button {
                            group.sku = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 6. Live Economics Radar Card

    private var economicsRadarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Unit_Economics_Title", alter: "تحليل التكلفة والوفورات للوحدة"), systemImage: "chart.xyaxis.line")
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primary)

            HStack(spacing: 12) {
                // Per-Piece Breakdown Pill
                if let perPiece = economics.pricePerPiece {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Unit_Per_Piece_Price", alter: "سعر القطعة الواحدة في هذه الوحدة"))
                            .font(.system(size: 11))
                            .foregroundStyle(AdminCommandInk.secondary)

                        Text(verbatim: String(format: "%.2f ر.ق / قطعة", perPiece))
                            .font(PPBrandFont.bold(size: 16))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AdminSurface.control.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Wholesale Savings Pill
                if let savings = economics.wholesaleSavingsPercent, savings > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Unit_Wholesale_Savings", alter: "وفر الجملة مقارنة بالتجزئة"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(uiColor: .systemTeal))

                        Text(verbatim: String(format: "%.0f%% وفر (%.2f ر.ق)", savings, economics.wholesaleSavingsAmount ?? 0))
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(Color(uiColor: .systemTeal))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(uiColor: .systemTeal).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Warning if wholesale is higher than retail
            if economics.isWholesaleMoreExpensive {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(uiColor: .ppWarning))
                    Text(Language.get("Unit_Wholesale_Warning_Higher", alter: "تنبيه: سعر الجملة أعلى من سعر التجزئة!"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .ppWarning))
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(AdminSurface.primarySoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 7. Retail Sales Channel Card

    private var retailChannelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $group.retailEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Retail_Selling_Channel", alter: "متاح للبيع بالتجزئة (قطاعي)"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .tint(AdminSurface.primary)

            if group.retailEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Retail_Selling_Price_QAR", alter: "سعر بيع التجزئة للوحدة (ر.ق)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    HStack {
                        TextField("0.00", text: $group.retailPriceText)
                            .font(PPBrandFont.bold(size: 22))
                            .englishNumericInput(text: $group.retailPriceText, allowsDecimal: true)

                        Text(verbatim: "ر.ق")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Toggle(isOn: $group.defaultForRetail) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 217/255, green: 119/255, blue: 6/255))
                        Text(Language.get("Default_Unit_For_Retail", alter: "الوحدة الافتراضية عند البيع بالتجزئة"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                .tint(AdminSurface.primary)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(group.retailEnabled ? AdminSurface.primary.opacity(0.3) : AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 8. Wholesale Sales Channel Card

    private var wholesaleChannelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $group.wholesaleEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .systemTeal))
                    Text(Language.get("Wholesale_Selling_Channel", alter: "متاح للبيع بالجملة"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .tint(Color(uiColor: .systemTeal))

            if group.wholesaleEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Wholesale_Selling_Price_QAR", alter: "سعر بيع الجملة للوحدة (ر.ق)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    HStack {
                        TextField("0.00", text: $group.wholesalePriceText)
                            .font(PPBrandFont.bold(size: 22))
                            .englishNumericInput(text: $group.wholesalePriceText, allowsDecimal: true)

                        Text(verbatim: "ر.ق")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Toggle(isOn: $group.defaultForWholesale) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(uiColor: .systemTeal))
                        Text(Language.get("Default_Unit_For_Wholesale", alter: "الوحدة الافتراضية عند البيع بالجملة"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                .tint(Color(uiColor: .systemTeal))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(group.wholesaleEnabled ? Color(uiColor: .systemTeal).opacity(0.3) : AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 9. Point of Sale (POS) Operational Beacon

    private var posMasterBeaconCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $group.active) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(group.active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 10, height: 10)
                        .shadow(color: (group.active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.6), radius: 4)

                    Text(Language.get("Unit_Active_Status", alter: "تفعيل هذه الوحدة في نقطة البيع"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .tint(Color(uiColor: .ppSuccess))

            Text(group.active
                ? Language.get("Unit_POS_Active_Sub", alter: "تظهر هذه الوحدة لموظفي الكاشير عند مسح الباركود أو اختيار الصنف")
                : Language.get("Unit_POS_Disabled_Sub", alter: "هذه الوحدة معطلة حالياً ولن تظهر على شاشات نقاط البيع"))
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Floating Save Dock

    private var tactileSaveDock: some View {
        VStack(spacing: 8) {
            if let errorText = localErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(Color(uiColor: .systemRed))
                    Text(errorText)
                        .font(AdminType.captionBold)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemRed).opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Button(action: onSave) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(Language.get("Unit_Save_Action", alter: "حفظ واعتماد وحدة البيع"))
                        .font(PPBrandFont.bold(size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(EditorPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Divider().background(AdminSurface.borderSubtle)
                }
        )
    }
}

// MARK: - iPad Spatial Command Quantity Group Inspector

private struct iPadQuantityGroupInspector: View {
    @Binding var group: PPQuantityGroupDraft
    @Binding var unitsText: String
    let canManageWholesale: Bool
    let economics: PPUnitEconomicsHelper
    let localErrorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        ZStack {
            // Centered High-Grade Floating Modal Console
            HStack(spacing: 28) {
                // Leading Pane: Live Commercial Vitrine & Unit Radar
                unitCommercialVitrine
                    .frame(width: 320)

                // Divider Line
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1)
                    .padding(.vertical, 20)

                // Trailing Pane: Interactive Configuration Deck
                unitConfigurationDeck
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.08), radius: 32, x: 0, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
            )
            .frame(maxWidth: 900, maxHeight: 720)
            .padding(24)
        }
    }

    // MARK: - Leading Pane: Unit Commercial Vitrine

    private var unitCommercialVitrine: some View {
        VStack(spacing: 16) {
            // Packaging Sigil
            PPIsometricPackageSigil(unitsCount: group.unitsPerGroup, isCompact: false)
                .padding(.top, 8)

            // Brand Typography
            VStack(spacing: 4) {
                Text(group.localizedName.isEmpty ? Language.get("Edit_Selling_Unit", alter: "وحدة البيع") : group.localizedName)
                    .font(Font.custom("Beiruti-Bold", size: 24))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !group.nameEn.isEmpty {
                    Text(group.nameEn)
                        .font(AdminType.callout.monospaced())
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }

            // Physical Multiplier Formula Pill
            HStack(spacing: 6) {
                Image(systemName: "equal.circle.fill")
                    .foregroundStyle(AdminSurface.primary)
                Text(verbatim: "1 \(group.localizedName) = \(group.unitsPerGroup) \(Language.get("Pieces", alter: "حبات"))")
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: Capsule())

            Divider()
                .padding(.horizontal, 16)

            // Economics Matrix
            VStack(spacing: 10) {
                if let perPiece = economics.pricePerPiece {
                    HStack {
                        Text(Language.get("Unit_Per_Piece_Price", alter: "سعر الحبة:"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Spacer()
                        Text(verbatim: String(format: "%.2f ر.ق", perPiece))
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }

                if group.retailEnabled && group.retailPrice > 0 {
                    HStack {
                        Text(Language.get("Retail", alter: "التجزئة:"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Spacer()
                        Text(verbatim: "\(group.retailPriceText) ر.ق")
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }
                }

                if group.wholesaleEnabled && group.wholesalePrice > 0 {
                    HStack {
                        Text(Language.get("Wholesale", alter: "الجملة:"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Spacer()
                        Text(verbatim: "\(group.wholesalePriceText) ر.ق")
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(Color(uiColor: .systemTeal))
                    }

                    if let savings = economics.wholesaleSavingsPercent, savings > 0 {
                        HStack {
                            Text(Language.get("Savings", alter: "وفر الجملة:"))
                                .font(AdminType.caption2)
                                .foregroundStyle(Color(uiColor: .systemTeal))
                            Spacer()
                            Text(verbatim: String(format: "%.0f%%", savings))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(uiColor: .systemTeal))
                        }
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()

            // Channels Presence Matrix
            HStack(spacing: 8) {
                // POS Channel Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(group.active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 7, height: 7)
                    Text(verbatim: "POS")
                        .font(AdminType.caption2Bold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background((group.active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12), in: Capsule())

                // Retail Default Pill
                if group.retailEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: group.defaultForRetail ? "crown.fill" : "cart.fill")
                            .font(.system(size: 9))
                        Text(group.defaultForRetail ? Language.get("Default", alter: "افتراضي") : Language.get("Retail", alter: "تجزئة"))
                            .font(AdminType.caption2)
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }

                // Wholesale Default Pill
                if group.wholesaleEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: group.defaultForWholesale ? "crown.fill" : "shippingbox.fill")
                            .font(.system(size: 9))
                        Text(group.defaultForWholesale ? Language.get("Default", alter: "افتراضي") : Language.get("Wholesale", alter: "جملة"))
                            .font(AdminType.caption2)
                    }
                    .foregroundStyle(Color(uiColor: .systemTeal))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .systemTeal).opacity(0.12), in: Capsule())
                }
            }

            // Monospace Barcode Chip
            if !group.barcode.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "barcode")
                        .font(.system(size: 11))
                    Text(group.barcode)
                        .font(AdminType.caption2.monospaced())
                }
                .foregroundStyle(AdminCommandInk.tertiary)
            }
        }
        .padding(8)
    }

    // MARK: - Trailing Pane: Configuration Deck

    private var unitConfigurationDeck: some View {
        VStack(spacing: 12) {
            // Top Bar
            HStack {
                Text(Language.get("Edit_Selling_Unit", alter: "وحدة البيع"))
                    .font(Font.custom("Beiruti-Bold", size: 22))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Button(Language.get("Cancel", alter: "إلغاء"), action: onCancel)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .keyboardShortcut(.escape, modifiers: [])

                Button(action: onSave) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Unit_Save_Action", alter: "حفظ واعتماد (⌘S)"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(EditorPressStyle())
                .keyboardShortcut("s", modifiers: .command)
            }

            Divider()

            // Scrollable Settings
            ScrollView {
                VStack(spacing: 16) {
                    // Archetypes Row
                    VStack(alignment: .leading, spacing: 6) {
                        Label(Language.get("Unit_Archetypes_Title", alter: "أنماط التعبئة والتغليف السريعة"), systemImage: "sparkles")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(PPUnitArchetype.allArchetypes) { archetype in
                                    let isSelected = group.unitsPerGroup == archetype.defaultMultiplier &&
                                        (group.nameAr == archetype.nameAr || group.nameEn == archetype.nameEn)

                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        withAnimation(.spring(response: 0.3)) {
                                            group.nameAr = archetype.nameAr
                                            group.nameEn = archetype.nameEn
                                            group.unitsPerGroup = archetype.defaultMultiplier
                                            unitsText = archetype.defaultMultiplier.englishDigits
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: archetype.icon)
                                                .font(.system(size: 12, weight: .bold))
                                            Text(Language.isRTL() ? archetype.nameAr : archetype.nameEn)
                                                .font(AdminType.captionBold)
                                            Text(verbatim: "\(archetype.defaultMultiplier)x")
                                                .font(.system(size: 10))
                                                .opacity(0.85)
                                        }
                                        .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(EditorPressStyle())
                                }
                            }
                        }
                    }

                    // Names Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Group_Name_Ar", alter: "اسم الوحدة (عربي)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)

                            TextField(Language.get("e.g. Carton", alter: "مثال: كرتون"), text: $group.nameAr)
                                .font(AdminType.body)
                                .environment(\.layoutDirection, .rightToLeft)
                                .padding(10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .forceKeyboardLanguage(.arabic)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Group_Name_En", alter: "اسم الوحدة (إنجليزي)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)

                            TextField("e.g. Carton", text: $group.nameEn)
                                .font(AdminType.body)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .forceKeyboardLanguage(.english)
                        }
                    }

                    // Multiplier Row + Jump Matrix
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("Units_Per_Group_Count", alter: "عدد الحبات في هذه الوحدة (القطع الأساسية)"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)

                        HStack(spacing: 8) {
                            Button {
                                let current = Int(unitsText) ?? 1
                                if current > 1 {
                                    unitsText = (current - 1).englishDigits
                                    group.unitsPerGroup = current - 1
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 38)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(EditorPressStyle())

                            TextField("1", text: $unitsText)
                                .font(PPBrandFont.bold(size: 20))
                                .multilineTextAlignment(.center)
                                .frame(width: 70)
                                .englishNumericInput(text: $unitsText, allowsDecimal: false)
                                .padding(8)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onChange(of: unitsText) { newVal in
                                    if let parsed = Int(newVal), parsed >= 1 {
                                        group.unitsPerGroup = parsed
                                    }
                                }

                            Button {
                                let current = Int(unitsText) ?? 1
                                unitsText = (current + 1).englishDigits
                                group.unitsPerGroup = current + 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 38)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(EditorPressStyle())

                            Spacer()

                            // Jump pills
                            HStack(spacing: 6) {
                                ForEach(Self.jumpMultipliers, id: \.self) { count in
                                    ipadMultiplierJumpPill(for: count)
                                }
                            }
                        }
                    }

                    // Barcode & SKU Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Group_Barcode", alter: "باركود المجموعة (اختياري)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)

                            HStack(spacing: 6) {
                                Image(systemName: "barcode")
                                    .foregroundStyle(AdminCommandInk.secondary)
                                TextField(Language.get("Barcode", alter: "الباركود"), text: $group.barcode)
                                    .font(AdminType.body.monospaced())
                                    .englishNumericInput(text: $group.barcode, allowsDecimal: false)

                                AdminBarcodeScanButton { scannedCode in
                                    group.barcode = scannedCode
                                }
                            }
                            .padding(8)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Language.get("Group_SKU", alter: "رمز الصنف SKU"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Spacer()
                                if group.sku.isEmpty {
                                    Button {
                                        let prefix = group.nameEn.filter { $0.isLetter }.prefix(4).uppercased()
                                        let tag = prefix.isEmpty ? "UNIT" : String(prefix)
                                        group.sku = "\(tag)-\(group.unitsPerGroup)X-\(Int.random(in: 100...999))"
                                    } label: {
                                        Text(Language.get("Generate_SKU_Auto", alter: "توليد"))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(AdminSurface.primary)
                                    }
                                }
                            }

                            TextField("SKU", text: $group.sku)
                                .font(AdminType.body.monospaced())
                                .padding(10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    // Channels Section
                    HStack(alignment: .top, spacing: 12) {
                        // Retail Channel Card
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $group.retailEnabled) {
                                Label(Language.get("Retail_Selling_Channel", alter: "التجزئة (قطاعي)"), systemImage: "cart.fill")
                                    .font(AdminType.subheadlineBold)
                            }
                            .tint(AdminSurface.primary)

                            if group.retailEnabled {
                                HStack {
                                    TextField("0.00", text: $group.retailPriceText)
                                        .font(PPBrandFont.bold(size: 18))
                                        .englishNumericInput(text: $group.retailPriceText, allowsDecimal: true)
                                    Text(verbatim: "ر.ق")
                                        .font(AdminType.caption)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                                .padding(10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Toggle(isOn: $group.defaultForRetail) {
                                    Text(Language.get("Default_Unit_For_Retail", alter: "الوحدة الافتراضية"))
                                        .font(AdminType.caption)
                                }
                                .tint(AdminSurface.primary)
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
                        )

                        // Wholesale Channel Card (if allowed)
                        if canManageWholesale {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: $group.wholesaleEnabled) {
                                    Label(Language.get("Wholesale_Selling_Channel", alter: "الجملة والشركات"), systemImage: "shippingbox.fill")
                                        .font(AdminType.subheadlineBold)
                                }
                                .tint(Color(uiColor: .systemTeal))

                                if group.wholesaleEnabled {
                                    HStack {
                                        TextField("0.00", text: $group.wholesalePriceText)
                                            .font(PPBrandFont.bold(size: 18))
                                            .englishNumericInput(text: $group.wholesalePriceText, allowsDecimal: true)
                                        Text(verbatim: "ر.ق")
                                            .font(AdminType.caption)
                                            .foregroundStyle(AdminCommandInk.secondary)
                                    }
                                    .padding(10)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Toggle(isOn: $group.defaultForWholesale) {
                                        Text(Language.get("Default_Unit_For_Wholesale", alter: "الوحدة الافتراضية"))
                                            .font(AdminType.caption)
                                    }
                                    .tint(Color(uiColor: .systemTeal))
                                }
                            }
                            .padding(12)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
                            )
                        }
                    }

                    // POS Master Switch
                    HStack {
                        Circle()
                            .fill(group.active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                            .frame(width: 8, height: 8)

                        Text(Language.get("Unit_Active_Status", alter: "تفعيل هذه الوحدة في نقطة البيع (POS)"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.primaryText)

                        Spacer()

                        Toggle("", isOn: $group.active)
                            .labelsHidden()
                            .tint(Color(uiColor: .ppSuccess))
                    }
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
                    )

                    // Error Message Banner (if any)
                    if let err = localErrorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(Color(uiColor: .systemRed))
                            Text(err)
                                .font(AdminType.captionBold)
                                .foregroundStyle(Color(uiColor: .systemRed))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemRed).opacity(0.10), in: Capsule())
                    }

                    // Delete Action (if allowed)
                    if let onDelete = onDelete {
                        Button(role: .destructive, action: onDelete) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text(Language.get("Delete_Selling_Unit", alter: "حذف وحدة البيع هذه (⌘⌫)"))
                            }
                            .font(AdminType.captionBold)
                            .foregroundStyle(Color(uiColor: .systemRed))
                            .padding(.vertical, 8)
                        }
                        .keyboardShortcut(.delete, modifiers: .command)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private static let jumpMultipliers: [Int] = [1, 6, 12, 24, 50, 100]

    @ViewBuilder
    private func ipadMultiplierJumpPill(for count: Int) -> some View {
        let isCur = group.unitsPerGroup == count
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3)) {
                group.unitsPerGroup = count
                unitsText = count.englishDigits
            }
        } label: {
            Text(verbatim: "\(count)")
                .font(AdminType.caption2Bold)
                .foregroundStyle(isCur ? Color.white : AdminCommandInk.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isCur ? AdminSurface.primary : AdminSurface.control)
                )
        }
        .buttonStyle(EditorPressStyle())
    }
}

private struct PPAccessorySpeciesPickerSheet: View {
    let speciesList: [MainKindsModel]
    let selectedSpecies: MainKindsModel?
    let onSelect: (MainKindsModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var filtered: [MainKindsModel] {
        if search.isEmpty { return speciesList }
        return speciesList.filter { $0.kindName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    // Custom Luxury Search Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        TextField(Language.get("SearchSpecies", alter: "ابحث عن نوع أو فئة الحيوان..."), text: $search)
                            .font(AdminType.callout)
                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminCommandInk.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Results Scroll List
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filtered.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "pawprint.circle")
                                        .font(.system(size: 40))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                    Text(Language.get("NoSpeciesFound", alter: "لا توجد فئات مطابقة للبحث"))
                                        .font(AdminType.calloutBold)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                                .padding(.top, 40)
                            } else {
                                ForEach(filtered, id: \.id) { species in
                                    let isSelected = selectedSpecies?.id == species.id
                                    let subKindsCount = (species.subKindsArray as? [SubKindModel])?.count ?? 0

                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        onSelect(species)
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                                    .frame(width: 42, height: 42)
                                                Image(systemName: "pawprint.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(species.kindName)
                                                    .font(AdminType.headline)
                                                    .foregroundStyle(AdminSurface.primaryText)

                                                if subKindsCount > 0 {
                                                    Text(verbatim: "\(subKindsCount.englishDigits) " + Language.get("BreedsAvailable", alter: "سلالة مسجلة"))
                                                        .font(AdminType.caption2)
                                                        .foregroundStyle(AdminCommandInk.secondary)
                                                }
                                            }

                                            Spacer()

                                            if isSelected {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(AdminSurface.primary)
                                            } else {
                                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(AdminCommandInk.tertiary)
                                            }
                                        }
                                        .padding(14)
                                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.75)
                                        )
                                    }
                                    .buttonStyle(EditorPressStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(Language.get("SelectSpecies", alter: "اختر نوع وفئة الحيوان"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct PPAccessoryBreedPickerSheet: View {
    let breedList: [SubKindModel]
    let selectedBreed: SubKindModel?
    let onSelect: (SubKindModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var filtered: [SubKindModel] {
        if search.isEmpty { return breedList }
        return breedList.filter { $0.subKindName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    // Custom Luxury Search Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        TextField(Language.get("SearchBreed", alter: "ابحث عن السلالة الفرعية..."), text: $search)
                            .font(AdminType.callout)
                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminCommandInk.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Results Scroll List
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filtered.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "tag.circle")
                                        .font(.system(size: 40))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                    Text(Language.get("NoBreedFound", alter: "لا توجد سلالات مطابقة"))
                                        .font(AdminType.calloutBold)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                                .padding(.top, 40)
                            } else {
                                ForEach(filtered, id: \.id) { breed in
                                    let isSelected = selectedBreed?.id == breed.id

                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        onSelect(breed)
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                                    .frame(width: 38, height: 38)
                                                Image(systemName: "tag.fill")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)
                                            }

                                            Text(breed.subKindName)
                                                .font(AdminType.headline)
                                                .foregroundStyle(AdminSurface.primaryText)

                                            Spacer()

                                            if isSelected {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(AdminSurface.primary)
                                            }
                                        }
                                        .padding(14)
                                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.75)
                                        )
                                    }
                                    .buttonStyle(EditorPressStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(Language.get("SelectBreed", alter: "اختر السلالة الفرعية"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct PPAccessoryStorePickerSheet: View {
    let stores: [(id: String, name: String)]
    let selectedStoreID: String
    let onSelect: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(stores, id: \.id) { store in
                            let isSelected = selectedStoreID == store.id
                            let isMain = store.id == "main_store"

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onSelect(store.id, store.name)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: isMain ? "building.2.fill" : "storefront.fill")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(isSelected ? .white : AdminSurface.primary)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.name)
                                            .font(AdminType.headline)
                                            .foregroundStyle(AdminSurface.primaryText)

                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(uiColor: .ppSuccess))
                                                .frame(width: 6, height: 6)
                                            Text(isMain ? Language.get("MainBranch", alter: "الفرع الرئيسي") : Language.get("SubBranch", alter: "فرع معتمد"))
                                                .font(AdminType.caption2)
                                                .foregroundStyle(AdminCommandInk.secondary)
                                        }
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(AdminSurface.primary)
                                    }
                                }
                                .padding(16)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.75)
                                )
                            }
                            .buttonStyle(EditorPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }
            .navigationTitle(Language.get("SelectStore", alter: "اختر الفرع / المتجر المالك"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

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

// MARK: - Live Pet Intake Experience

/// Keeps the established editor and state owner intact while routing only the
/// dedicated live-pet catalog path into the task-led intake experience.
struct PPAccessoryEditorExperienceRouter: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel

    init(viewModel: PPAccessoryEditorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.isLivePet && !viewModel.showTypeRow {
                PPLivePetIntakeJourney(viewModel: viewModel)
            } else if !viewModel.showTypeRow
                        && (viewModel.selectedKind == .typeAccessory || viewModel.selectedKind == .typeFood) {
                PPAccessoryFoodIntakeJourney(viewModel: viewModel)
            } else {
                PPAccessoryEditorScreen(viewModel: viewModel)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .interactiveDismissDisabled(viewModel.blocksDismissal)
        .background {
            PPUIKitDismissalGuard(isBlocked: viewModel.blocksDismissal)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

private struct PPUIKitDismissalGuard: UIViewControllerRepresentable {
    let isBlocked: Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.update(isBlocked: isBlocked)
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.update(isBlocked: isBlocked)
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private var isBlocked = false
        private var didDisableInteractivePop = false
        private var dismissTap: UITapGestureRecognizer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyGuard()
            setupKeyboardDismissTap()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyGuard()
            setupKeyboardDismissTap()
        }

        func update(isBlocked: Bool) {
            self.isBlocked = isBlocked
            DispatchQueue.main.async { [weak self] in
                self?.applyGuard()
            }
        }

        private func setupKeyboardDismissTap() {
            guard dismissTap == nil, let hostView = parent?.view else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            hostView.addGestureRecognizer(tap)
            dismissTap = tap
        }

        @objc private func handleDismissTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var current = touch.view
            while let v = current {
                if v is UITextField || v is UITextView {
                    return false
                }
                current = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        private func applyGuard() {
            var ancestor = parent
            while let controller = ancestor {
                controller.isModalInPresentation = isBlocked
                ancestor = controller.parent
            }

            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            if isBlocked {
                gesture.isEnabled = false
                didDisableInteractivePop = true
            } else if didDisableInteractivePop {
                gesture.isEnabled = true
                didDisableInteractivePop = false
            }
        }
    }
}

/// Derived, per-animal completeness. Mirrors the required-field set that
/// `validate()` and the Infra unit validator already enforce; it does not
/// add or relax a rule. Gender is deliberately *not* required, because the
/// server contract defaults an unsent gender to `UNSPECIFIED`.
struct PPUnitReadiness {
    let satisfied: Int
    let required: Int
    let missingLabels: [String]
    let isDuplicateIdentity: Bool
    let isUntouched: Bool
    let genderRecorded: Bool
    let statusSummary: String
    let tint: Color

    var isSubmittable: Bool { satisfied == required && !isDuplicateIdentity }
    var progress: Double { required == 0 ? 1 : Double(satisfied) / Double(required) }
}

private struct PPLivePetIntakeJourney: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: FocusedField?

    @State private var showJourneyMap = false
    @State private var expandedUnitID: String?
    @State private var previewNotesExpanded = false
    @State private var stageMessage: String?
    @State private var previewMedia: PPLivePetPreviewMedia?
    @State private var unitPhotoTargetID: String?
    @State private var showUnitPhotoSource = false
    @State private var showUnitPhotoLibrary = false
    @State private var showUnitPhotoCamera = false
    @State private var showCameraAccessAlert = false
    @State private var showQuantityAlert = false
    @State private var quantityAlertText = ""
    @State private var bilingualLanguage: PPBilingualLanguage = .arabic
    @Namespace private var genderSelectionNamespace

    private enum FocusedField: Hashable {
        case name
        case description
        case standardPrice
        case discountPercent
        case discountAmount
        case wholesalePrice
        case groupCost
        case supplier
        case notes
        // Per-animal fields are addressed by draft id so focus survives
        // reordering, cloning and removal inside the roster.
        case unitRing(String)
        case unitSellingPrice(String)
        case unitPurchaseCost(String)
        case unitSupplier(String)
        case unitNotes(String)
    }

    var body: some View {
        ZStack {
            intakeBackground

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            intakeHeader
                                .accessibilitySortPriority(4)

                            VStack(spacing: AdminSpacing.base) {
                            journeyCompass
                                .accessibilitySortPriority(3)

                            feedbackArea

                            currentStageScene
                                .id(viewModel.activeStage)
                                .transition(
                                    accessibilityReduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                                )
                                .allowsHitTesting(!viewModel.hasPendingLivePetRecovery)
                                .opacity(viewModel.hasPendingLivePetRecovery ? 0.72 : 1)
                                .accessibilitySortPriority(2)
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.sm)
                        .padding(.bottom, 140)
                    }
                }
                .scrollDismissesKeyboardCompat()
                .onChange(of: focusedField) { field in
                    scrollToFocusedField(proxy: proxy, targetField: field)
                }
                .onChange(of: bilingualLanguage) { _ in
                    scrollToFocusedField(proxy: proxy)
                }
            }
            .id(viewModel.activeStage)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionDock
                    .accessibilitySortPriority(1)
            }
            .allowsHitTesting(!viewModel.isSubmitting)
            .accessibilityHidden(viewModel.isSubmitting)

            if viewModel.isSubmitting {
                submissionOverlay
                    .transition(.opacity)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showJourneyMap) {
            PPLivePetJourneyMapSheet(
                activeStage: viewModel.activeStage,
                completedStages: Set(PPEditorStage.allCases.filter { validationMessage(for: $0) == nil }),
                onSelect: { stage in
                    showJourneyMap = false
                    move(to: stage)
                }
            )
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            PPLivePetPhotoPicker(maxSelection: max(0, 9 - viewModel.totalImageCount)) { images, failedCount in
                viewModel.addPickedImages(images)
                guard failedCount > 0 else { return }
                let message = String(
                    format: tr("LivePetIntake_PhotoImportFailureFormat", "تعذر استيراد %ld من الصور المحددة. أعد المحاولة للصور الناقصة."),
                    failedCount
                )
                stageMessage = message
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        .confirmationDialog(
            tr("LivePetIntake_UnitPhotoSourceTitle", "صورة هذا الحيوان"),
            isPresented: $showUnitPhotoSource,
            titleVisibility: .visible
        ) {
            Button(tr("LivePetIntake_UnitPhotoCamera", "التقاط صورة")) {
                requestUnitPhotoCamera()
            }
            Button(tr("LivePetIntake_UnitPhotoLibrary", "اختيار من مكتبة الصور")) {
                showUnitPhotoLibrary = true
            }
            Button(tr("Cancel", "إلغاء"), role: .cancel) {}
        } message: {
            Text(tr(
                "LivePetIntake_UnitPhotoSourceMessage",
                "سترتبط الصورة بسجل هذا الحيوان فقط ولن تُنسخ إلى الحيوانات الأخرى."
            ))
        }
        .sheet(isPresented: $showUnitPhotoLibrary) {
            PPLivePetPhotoPicker(maxSelection: 1) { images, failedCount in
                if let image = images.first {
                    acceptUnitPhoto(image)
                } else if failedCount > 0 {
                    presentUnitPhotoMessage(tr(
                        "LivePetIntake_UnitPhotoImportFailed",
                        "تعذر استيراد الصورة المحددة. اختر صورة أخرى وحاول مجدداً."
                    ))
                }
            }
        }
        .fullScreenCover(isPresented: $showUnitPhotoCamera) {
            PPLivePetCameraPicker { image in
                acceptUnitPhoto(image)
            }
        }
        .alert(
            tr("LivePetIntake_UnitPhotoCameraPermissionTitle", "السماح باستخدام الكاميرا"),
            isPresented: $showCameraAccessAlert
        ) {
            Button(tr("LivePetIntake_OpenSettings", "فتح الإعدادات")) {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(settingsURL)
            }
            Button(tr("Cancel", "إلغاء"), role: .cancel) {}
        } message: {
            Text(tr(
                "LivePetIntake_UnitPhotoCameraPermissionMessage",
                "فعّل إذن الكاميرا من الإعدادات لالتقاط صورة خاصة بهذا الحيوان، أو اختر صورة من المكتبة."
            ))
        }
        .sheet(isPresented: $viewModel.showSpeciesPicker) {
            PPLivePetChoiceSheet(
                title: tr("LivePetIntake_SelectSpecies", "اختر نوع الحيوان"),
                subtitle: tr("LivePetIntake_SelectSpeciesSub", "ابحث في التصنيف المعتمد للكتالوج."),
                searchPrompt: tr("LivePetIntake_SearchSpecies", "ابحث عن نوع أو فئة"),
                emptyTitle: tr("LivePetIntake_NoSpecies", "لا توجد أنواع مطابقة"),
                selectedID: viewModel.selectedMainKind.map { String($0.id) },
                choices: viewModel.availableMainKinds.map { kind in
                    PPLivePetChoice(
                        id: String(kind.id),
                        title: kind.kindName,
                        subtitle: String(
                            format: tr("LivePetIntake_BreedCount", "%ld سلالة مسجلة"),
                            (kind.subKindsArray as? [SubKindModel])?.count ?? 0
                        ),
                        symbol: "pawprint.fill"
                    )
                },
                onRefresh: {
                    viewModel.loadMainKinds(forceServer: true)
                },
                onSelect: { selectedID in
                    viewModel.selectedMainKind = viewModel.availableMainKinds.first { String($0.id) == selectedID }
                    viewModel.showSpeciesPicker = false
                }
            )
            .onAppear {
                viewModel.loadMainKinds(forceServer: true)
            }
        }
        .sheet(isPresented: $viewModel.showBreedPicker) {
            PPLivePetChoiceSheet(
                title: tr("LivePetIntake_SelectBreed", "اختر السلالة"),
                subtitle: tr("LivePetIntake_SelectBreedSub", "السلالة اختيارية ويمكن إضافتها لاحقاً."),
                searchPrompt: tr("LivePetIntake_SearchBreed", "ابحث عن سلالة"),
                emptyTitle: tr("LivePetIntake_NoBreeds", "لا توجد سلالات مطابقة"),
                selectedID: viewModel.selectedSubKind.map { String($0.id) },
                choices: viewModel.availableSubKinds.map { breed in
                    PPLivePetChoice(
                        id: String(breed.id),
                        title: breed.subKindName,
                        subtitle: nil,
                        symbol: "tag.fill"
                    )
                },
                onRefresh: {
                    if let main = viewModel.selectedMainKind {
                        viewModel.fetchFreshSubKinds(for: main)
                    } else {
                        viewModel.loadMainKinds(forceServer: true)
                    }
                },
                onSelect: { selectedID in
                    viewModel.selectedSubKind = viewModel.availableSubKinds.first { String($0.id) == selectedID }
                    viewModel.showBreedPicker = false
                }
            )
            .onAppear {
                if let main = viewModel.selectedMainKind {
                    viewModel.fetchFreshSubKinds(for: main)
                }
            }
        }
        .sheet(isPresented: $viewModel.showStorePicker) {
            PPBranchSelectionGateView(
                title: tr("LivePetIntake_SelectBranch", "اختر الفرع المالك"),
                subtitle: tr("LivePetIntake_SelectBranchSub", "سيُنسب المخزون والحركة الافتتاحية إلى هذا الفرع."),
                selectedBranchID: viewModel.selectedStoreID,
                allowGlobalAccess: false
            ) { selectedBranch in
                viewModel.selectedStoreID = selectedBranch.branchID
                viewModel.selectedStoreName = selectedBranch.localizedName()
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $viewModel.showQuantityGroupInspector) {
            if let group = viewModel.selectedQuantityGroupForEditing {
                PPQuantityGroupInspectorSheet(
                    group: group,
                    canManageWholesale: viewModel.canManageWholesale,
                    onSave: { updated in
                        viewModel.saveQuantityGroup(updated)
                    },
                    onDelete: viewModel.quantityGroups.count > 1 ? {
                        viewModel.deleteQuantityGroup(id: group.id)
                    } : nil
                )
            }
        }
        .fullScreenCover(item: $previewMedia) { media in
            PPLivePetMediaPreview(media: media)
        }
        .onAppear {
            if expandedUnitID == nil {
                expandedUnitID = viewModel.livePetUnits.first?.id
            }
        }
        .onChange(of: viewModel.isSubmitting) { submitting in
            guard submitting else { return }
            UIAccessibility.post(
                notification: .screenChanged,
                argument: tr("LivePetIntake_Submitting", "جارٍ حفظ السجل بأمان")
            )
        }
        .onChange(of: viewModel.errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .onChange(of: viewModel.saveSuccessMessage) { message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func promptQuantityEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: tr("EditQuantity", "تعديل الكمية"),
            subtitle: tr("EnterQuantityPrompt", "أدخل كمية المخزون المتاحة لهذا الصنف"),
            placeholder: tr("LivePetIntake_QuantityLabel", "عدد الحيوانات في المجموعة"),
            initialText: "\(viewModel.quantity)",
            confirmText: tr("Save", "حفظ"),
            cancelText: tr("Cancel", "إلغاء"),
            secureEntry: false,
            keyboardType: .numberPad
        ) { text in
            guard let text else { return }
            let normalized = text.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(normalized) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    viewModel.quantity = max(1, val)
                }
            }
        }
    }

    // MARK: Frame

    private var intakeBackground: some View {
        AdminSurface.background
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .accessibilityHidden(true)
    }

    private func scrollToFocusedField(proxy: ScrollViewProxy, targetField: FocusedField? = nil) {
        let field = targetField ?? focusedField
        guard let field = field else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(field, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.20)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
    }

    private func showDiscardAlert() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Discard_Changes_Title", alter: "تنبيه"),
            subtitle: Language.get("Discard_Changes_Message", alter: "ستفقد التعديلات غير المحفوظة إذا غادرت الآن."),
            confirmButton: Language.get("Discard_Changes_Confirm", alter: "مغادرة وتجاهل"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.discardChangesAndDismiss()
            },
            cancelBlock: nil
        )
    }

    private func showRemoveAnimalAlert(for id: String) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("LivePetIntake_RemoveAnimalTitle", alter: "إزالة سجل الحيوان؟"),
            subtitle: Language.get("LivePetIntake_RemoveAnimalMessage", alter: "سيُحذف هذا السجل من الإدخال الحالي فقط."),
            confirmButton: Language.get("LivePetIntake_RemoveAnimal", alter: "إزالة الحيوان"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.removeLivePetUnit(id: id)
            },
            cancelBlock: nil
        )
    }

    private func presentUnitPhotoSource(for unitID: String) {
        focusedField = nil
        guard viewModel.canManageStock else {
            presentUnitPhotoMessage(tr(
                "LivePetIntake_UnitPhotoPermissionRequired",
                "تحتاج إلى صلاحية إدارة المخزون لإرفاق صورة الحيوان."
            ))
            return
        }
        unitPhotoTargetID = unitID
        showUnitPhotoSource = true
    }

    private func acceptUnitPhoto(_ image: UIImage) {
        guard let unitID = unitPhotoTargetID else { return }
        if let errorMessage = viewModel.setLivePetUnitPhoto(image, unitID: unitID) {
            presentUnitPhotoMessage(errorMessage)
        } else {
            stageMessage = nil
            let message = tr(
                "LivePetIntake_UnitPhotoSelectedAnnouncement",
                "تم إرفاق الصورة بهذا الحيوان فقط."
            )
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func presentUnitPhotoMessage(_ message: String) {
        stageMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func requestUnitPhotoCamera() {
        guard unitPhotoTargetID != nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentUnitPhotoMessage(tr(
                "LivePetIntake_UnitPhotoCameraUnavailable",
                "الكاميرا غير متاحة على هذا الجهاز. اختر صورة من المكتبة."
            ))
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showUnitPhotoCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showUnitPhotoCamera = true
                    } else {
                        showCameraAccessAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraAccessAlert = true
        @unknown default:
            showCameraAccessAlert = true
        }
    }

    private var intakeHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            Button {
                if viewModel.hasUnsavedChanges {
                    showDiscardAlert()
                } else {
                    viewModel.discardChangesAndDismiss()
                }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(AdminSurface.hairline.opacity(0.8), lineWidth: 0.75)
                    )
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .disabled(viewModel.hasPendingLivePetRecovery)
            .accessibilityLabel(tr("Back", "رجوع"))
            .accessibilityHint(viewModel.hasUnsavedChanges
                ? tr("LivePetIntake_BackUnsavedHint", "يعرض تأكيداً قبل تجاهل التعديلات")
                : tr("LivePetIntake_BackHint", "يعود إلى قائمة الحيوانات الحية"))

            VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                Text(viewModel.editingAccessory == nil
                    ? tr("LivePetIntake_Title", "إدخال حيوان حي")
                    : tr("LivePetIntake_EditTitle", "تحديث سجل حيوان حي"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                HStack(spacing: AdminSpacing.xs) {
                    Circle()
                        .fill(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                        .frame(width: 6, height: 6)
                    Text(viewModel.isDraft
                        ? tr("LivePetIntake_DraftState", "مسودة غير ظاهرة")
                        : tr("LivePetIntake_VisibleState", "جاهز للإتاحة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer(minLength: AdminSpacing.xs)

            Button {
                showJourneyMap = true
            } label: {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .disabled(viewModel.hasPendingLivePetRecovery)
            .accessibilityLabel(tr("LivePetIntake_JourneyMap", "خريطة خطوات الإدخال"))
            .accessibilityHint(tr("LivePetIntake_JourneyMapHint", "يفتح جميع الخطوات وحالة اكتمالها"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.sm)
        .background(Color.clear)
    }

    private var journeyCompass: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
                Button {
                    showJourneyMap = true
                } label: {
                    VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                        Text(stageEyebrow(viewModel.activeStage).uppercased())
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primary)
                        Text(stageTitle(viewModel.activeStage))
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(stageQuestion(viewModel.activeStage))
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    format: tr("LivePetIntake_ProgressAccessibility", "الخطوة %ld من 4، %@"),
                    viewModel.activeStage.rawValue + 1,
                    stageTitle(viewModel.activeStage)
                ))
                .accessibilityHint(tr("LivePetIntake_JourneyMapHint", "يفتح جميع الخطوات وحالة اكتمالها"))

                Spacer(minLength: AdminSpacing.sm)

                Button {
                    showJourneyMap = true
                } label: {
                    compassCompletionBadge
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.xs) {
                    ForEach(PPEditorStage.allCases) { stage in
                        Button {
                            move(to: stage)
                        } label: {
                            stagePill(for: stage)
                        }
                        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                        .accessibilityAddTraits(stage == viewModel.activeStage ? .isSelected : [])
                    }
                }
            }
        }
        .padding(AdminSpacing.base)
        .background(
            LinearGradient(
                colors: [AdminSurface.surface, AdminSurface.primarySoft.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func stageEyebrow(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_StageOne", "الخطوة 1")
        case .bioVault: return tr("CatalogIntake_StageTwo", "الخطوة 2")
        case .pricing: return tr("CatalogIntake_StageThree", "الخطوة 3")
        case .governance: return tr("CatalogIntake_StageFour", "الخطوة 4")
        }
    }

    private func shortStageTitle(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_ShortIdentity", "الهوية")
        case .bioVault: return tr("CatalogIntake_ShortSpecs", "المواصفات")
        case .pricing: return tr("CatalogIntake_ShortPricing", "التسعير")
        case .governance: return tr("CatalogIntake_ShortRelease", "الإتاحة")
        }
    }

    @ViewBuilder
    private func stagePill(for stage: PPEditorStage) -> some View {
        let isCurrent = stage == viewModel.activeStage
        let isDone = validationMessage(for: stage) == nil
        let icon = isDone ? "checkmark.circle.fill" : stage.symbol
        let tint = progressColor(for: stage)
        HStack(spacing: AdminSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(shortStageTitle(stage))
                .font(AdminType.caption2Bold)
                .lineLimit(1)
        }
        .foregroundStyle(isCurrent ? Color.white : tint)
        .padding(.horizontal, AdminSpacing.sm)
        .frame(minHeight: 36)
        .background(
            isCurrent ? AdminSurface.primary : tint.opacity(0.10),
            in: Capsule()
        )
        .contentShape(Capsule())
    }

    private var compassCompletionBadge: some View {
        Text(String(
            format: tr("LivePetIntake_CompletedFormat", "%ld من 4 مكتملة"),
            completedStageCount
        ))
        .font(AdminType.caption2Bold)
        .foregroundStyle(AdminSurface.primary)
        .padding(.horizontal, AdminSpacing.sm)
        .frame(minHeight: 28)
        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private var feedbackArea: some View {
        if let error = viewModel.errorMessage, !error.isEmpty {
            feedbackBanner(
                message: error,
                symbol: "exclamationmark.triangle.fill",
                color: Color(uiColor: .ppError),
                dismiss: { viewModel.dismissSubmissionFeedback() },
                actionTitle: viewModel.submissionFailureActionTitle,
                action: { viewModel.performSubmissionFailureAction() }
            )
        } else if let message = stageMessage, !message.isEmpty {
            feedbackBanner(
                message: message,
                symbol: "arrow.down.circle.fill",
                color: Color(uiColor: .ppWarning),
                dismiss: { stageMessage = nil }
            )
        } else if let success = viewModel.saveSuccessMessage, !success.isEmpty {
            feedbackBanner(
                message: success,
                symbol: "checkmark.seal.fill",
                color: Color(uiColor: .ppSuccess),
                dismiss: nil
            )
        }
    }

    private func feedbackBanner(
        message: String,
        symbol: String,
        color: Color,
        dismiss: (() -> Void)?,
        actionTitle: String? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(message)
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    }
                    .accessibilityLabel(tr("Close", "إغلاق"))
                }
            }

            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.captionBold)
                        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.bordered)
                .tint(color)
            }
        }
        .padding(AdminSpacing.md)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var currentStageScene: some View {
        switch viewModel.activeStage {
        case .identity:
            identityScene
        case .bioVault:
            intakeScene
        case .pricing:
            pricingScene
        case .governance:
            releaseScene
        }
    }

    // MARK: Identity

    private var identityScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("LivePetIntake_IdentityEyebrow", "الهوية المرئية"),
            title: tr("LivePetIntake_IdentityTitle", "عرّف الحيوان كما سيجده الفريق والعملاء"),
            subtitle: tr("LivePetIntake_IdentitySubtitle", "ابدأ بصورة واضحة ثم ثبّت الاسم والتصنيف. الصورة اختيارية، أما الاسم والنوع فمطلوبان."),
            symbol: "pawprint.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                mediaCanvas

                Divider().background(AdminSurface.hairline)

                PPBilingualInputField(
                    title: tr("LivePetIntake_NameLabel", "اسم الحيوان أو الصنف"),
                    isRequired: true,
                    arabicText: $viewModel.name,
                    englishText: $viewModel.nameEn,
                    arabicPlaceholder: tr("LivePetIntake_NamePlaceholder", "مثال: كوكتيل لوتينو أليف"),
                    englishPlaceholder: "e.g. Tame Lutino Cockatiel",
                    selectedLanguage: $bilingualLanguage,
                    isFocused: focusedField == .name,
                    onFocusChange: { focused in
                        if focused { focusedField = .name }
                        else if focusedField == .name { focusedField = nil }
                    },
                    onSubmit: { focusedField = .description }
                )
                .id(FocusedField.name)

                taxonomyControls

                PPBilingualTextEditorField(
                    title: tr("LivePetIntake_DescriptionLabel", "وصف مختصر"),
                    isRequired: false,
                    arabicText: $viewModel.desc,
                    englishText: $viewModel.descEn,
                    arabicPlaceholder: tr("LivePetIntake_DescriptionPlaceholder", "السلوك، اللون، السمات التي يحتاج العميل إلى معرفتها…"),
                    englishPlaceholder: "Behavior, temperament, color traits, health notes for customers…",
                    selectedLanguage: $bilingualLanguage,
                    minHeight: 112,
                    isFocused: focusedField == .description,
                    onFocusChange: { focused in
                        if focused { focusedField = .description }
                        else if focusedField == .description { focusedField = nil }
                    }
                )
                .id(FocusedField.description)
            }
        }
    }

    private var mediaCanvas: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .center, spacing: AdminSpacing.sm) {
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(tr("LivePetIntake_MediaTitle", "صور الكتالوج"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(
                        format: tr("LivePetIntake_PhotoCount", "%ld من 9 صور"),
                        viewModel.totalImageCount
                    ))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                if viewModel.canAddImages {
                    Button {
                        focusedField = nil
                        viewModel.showImagePicker = true
                    } label: {
                        Label(tr("LivePetIntake_AddPhotos", "إضافة صور"), systemImage: "photo.badge.plus")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, AdminSpacing.md)
                            .frame(height: 34)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                }
            }

            primaryMediaHero

            if viewModel.totalImageCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AdminSpacing.sm) {
                        ForEach(Array(viewModel.existingImageURLs.enumerated()), id: \.offset) { index, urlString in
                            remoteMediaThumbnail(urlString: urlString, index: index)
                        }
                        ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, image in
                            localMediaThumbnail(image: image, index: index)
                        }
                    }
                    .padding(.vertical, AdminSpacing.xxs)
                }
                .accessibilityLabel(tr("LivePetIntake_MediaGallery", "معرض صور الحيوان"))
            }
        }
    }

    @ViewBuilder
    private var primaryMediaHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let firstURL = viewModel.existingImageURLs.first, let url = URL(string: firstURL) {
                AdminRemoteImage(url: url, contentMode: .fill) {
                    ZStack {
                        AdminSurface.control
                        ProgressView().tint(AdminSurface.primary)
                    }
                }
                .onTapGesture {
                    previewMedia = PPLivePetPreviewMedia(source: .remote(url))
                }
                .accessibilityAction {
                    previewMedia = PPLivePetPreviewMedia(source: .remote(url))
                }
            } else if let firstImage = viewModel.pickedImages.first {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFill()
                    .onTapGesture {
                        previewMedia = PPLivePetPreviewMedia(source: .local(firstImage))
                    }
                    .accessibilityAction {
                        previewMedia = PPLivePetPreviewMedia(source: .local(firstImage))
                    }
            } else {
                Button {
                    viewModel.showImagePicker = true
                } label: {
                    VStack(spacing: AdminSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.10))
                                .frame(width: 72, height: 72)
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)
                        }
                        VStack(spacing: AdminSpacing.xs) {
                            Text(tr("LivePetIntake_AddFirstPhoto", "أضف الصورة الأولى"))
                                .font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(tr("LivePetIntake_AddFirstPhotoSub", "صورة أفقية واضحة تمنح السجل هوية فورية"))
                                .font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            }

            if viewModel.totalImageCount > 0 {
                HStack(spacing: AdminSpacing.xs) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(tr("LivePetIntake_PrimaryPhoto", "الصورة الرئيسية"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AdminSpacing.sm)
                .frame(minHeight: 30)
                .background(Color.black.opacity(0.56), in: Capsule())
                .padding(AdminSpacing.md)
            }
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 260 : 190)
        .background(AdminSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.8), lineWidth: 0.75)
        )
        .clipped()
        .accessibilityLabel(viewModel.totalImageCount > 0
            ? tr("LivePetIntake_PrimaryPhoto", "الصورة الرئيسية")
            : tr("LivePetIntake_AddFirstPhoto", "أضف الصورة الأولى"))
        .accessibilityHint(viewModel.totalImageCount > 0
            ? tr("LivePetIntake_InspectPhotoHint", "اضغط لعرض الصورة بالحجم الكامل")
            : tr("LivePetIntake_AddPhotoHint", "يفتح مكتبة الصور"))
    }

    private func mediaPlaceholder(symbol: String) -> some View {
        ZStack {
            AdminSurface.control
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AdminSurface.secondaryText)
        }
    }

    private func remoteMediaThumbnail(urlString: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if let url = URL(string: urlString) {
                    previewMedia = PPLivePetPreviewMedia(source: .remote(url))
                }
            } label: {
                AdminRemoteImage(url: URL(string: urlString), contentMode: .fill, targetSize: CGSize(width: 82, height: 82)) {
                    mediaPlaceholder(symbol: "photo")
                }
                .frame(width: 82, height: 82)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(primaryThumbnailBorder(isPrimary: index == 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(index == 0
                ? tr("LivePetIntake_PrimaryPhoto", "الصورة الرئيسية")
                : String(format: tr("LivePetIntake_PhotoNumber", "الصورة %ld"), index + 1))
            .accessibilityHint(tr("LivePetIntake_InspectPhotoHint", "اضغط لعرض الصورة بالحجم الكامل"))

            removeMediaButton(
                accessibilityLabel: index == 0
                    ? tr("LivePetIntake_RemovePrimaryPhoto", "إزالة الصورة الرئيسية")
                    : String(format: tr("LivePetIntake_RemovePhotoNumber", "إزالة الصورة %ld"), index + 1)
            ) {
                viewModel.removeExistingImage(at: index)
            }
        }
        .frame(width: 88, height: 88)
    }

    private func localMediaThumbnail(image: UIImage, index: Int) -> some View {
        let displayIndex = viewModel.existingImageURLs.count + index
        return ZStack(alignment: .topTrailing) {
            Button {
                previewMedia = PPLivePetPreviewMedia(source: .local(image))
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(primaryThumbnailBorder(isPrimary: displayIndex == 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayIndex == 0
                ? tr("LivePetIntake_PrimaryPhoto", "الصورة الرئيسية")
                : String(format: tr("LivePetIntake_PhotoNumber", "الصورة %ld"), displayIndex + 1))
            .accessibilityHint(tr("LivePetIntake_InspectPhotoHint", "اضغط لعرض الصورة بالحجم الكامل"))

            removeMediaButton(
                accessibilityLabel: displayIndex == 0
                    ? tr("LivePetIntake_RemovePrimaryPhoto", "إزالة الصورة الرئيسية")
                    : String(format: tr("LivePetIntake_RemovePhotoNumber", "إزالة الصورة %ld"), displayIndex + 1)
            ) {
                viewModel.removePickedImage(at: index)
            }
        }
        .frame(width: 88, height: 88)
    }

    private func primaryThumbnailBorder(isPrimary: Bool) -> some View {
        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
            .strokeBorder(isPrimary ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isPrimary ? 2 : 0.75)
    }

    private func removeMediaButton(accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .ppError), in: Circle())
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var taxonomyControls: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("LivePetIntake_Taxonomy", "النوع والسلالة"), required: true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.sm) {
                        speciesButton
                        breedButton
                    }
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        speciesButton
                        breedButton
                    }
                }
            }

            if viewModel.isLoadingKinds {
                Label(tr("LivePetIntake_TaxonomyLoading", "جارٍ تحميل التصنيف المعتمد…"), systemImage: "arrow.triangle.2.circlepath")
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            } else if let error = viewModel.kindsErrorMessage, !error.isEmpty {
                HStack(alignment: .top, spacing: AdminSpacing.sm) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Color(uiColor: .ppWarning))
                    Text(error)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("Retry", "إعادة المحاولة")) {
                        viewModel.loadMainKinds()
                    }
                    .font(AdminType.captionBold)
                }
                .padding(AdminSpacing.sm)
                .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
            }
        }
    }

    private var speciesButton: some View {
        taxonomyButton(
            title: tr("LivePetIntake_Species", "نوع الحيوان"),
            value: viewModel.selectedMainKind?.kindName ?? tr("LivePetIntake_Select", "اختيار"),
            symbol: "pawprint.fill",
            enabled: !viewModel.isLoadingKinds
        ) {
            focusedField = nil
            viewModel.showSpeciesPicker = true
        }
    }

    private var breedButton: some View {
        taxonomyButton(
            title: tr("LivePetIntake_Breed", "السلالة (اختيارية)"),
            value: viewModel.selectedSubKind?.subKindName ?? tr("LivePetIntake_NotSelected", "غير محددة"),
            symbol: "tag.fill",
            enabled: viewModel.selectedMainKind != nil
        ) {
            focusedField = nil
            viewModel.showBreedPicker = true
        }
    }

    private func taxonomyButton(title: String, value: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? AdminSurface.primary : AdminSurface.secondaryText)
                    .frame(width: 30, height: 30)
                    .background((enabled ? AdminSurface.primary : AdminSurface.secondaryText).opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(title)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(value)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(enabled ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: AdminSpacing.xs)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.horizontal, AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(!enabled)
        .accessibilityLabel("\(title)، \(value)")
        .accessibilityHint(tr("LivePetIntake_ChooseHint", "يفتح قائمة الاختيار"))
    }

    // MARK: Intake

    private var intakeScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("LivePetIntake_IntakeEyebrow", "هوية المخزون"),
            title: tr("LivePetIntake_IntakeTitle", "اختر كيف سيُتتبّع الحيوان فعلياً"),
            subtitle: tr("LivePetIntake_IntakeSubtitle", "الحيوان الفردي يحتفظ بحلقة أو شريحة وسعر مستقل. المجموعة تتشارك كمية وسعراً واحداً. لا يمكن تغيير النمط بعد الإنشاء."),
            symbol: "shippingbox.and.arrow.backward.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                trackingModeSelector

                if viewModel.liveInventoryMode == .individual {
                    individualIntake
                } else {
                    quantityIntake
                }

                previewNotes
            }
        }
    }

    private var trackingModeSelector: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("LivePetIntake_TrackingMode", "نمط التتبع"), required: true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.sm) {
                        trackingModeCard(.individual)
                        trackingModeCard(.quantity)
                    }
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        trackingModeCard(.individual)
                        trackingModeCard(.quantity)
                    }
                }
            }

            if viewModel.isEditingLivePet {
                Label(
                    tr("LivePetIntake_TrackingLocked", "نمط التتبع ثابت بعد إنشاء السجل. تُدار الحيوانات الفردية من مساحة عمليات المخزون."),
                    systemImage: "lock.shield.fill"
                )
                .font(AdminType.caption)
                .foregroundStyle(Color(uiColor: .ppWarning))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func trackingModeCard(_ mode: PPLivePetInventoryMode) -> some View {
        let selected = viewModel.liveInventoryMode == mode
        let individual = mode == .individual
        return Button {
            guard !viewModel.isEditingLivePet else { return }
            viewModel.selectLiveInventoryMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                HStack {
                    Image(systemName: individual ? "number.square.fill" : "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? .white : AdminSurface.primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? .white : AdminSurface.secondaryText)
                }
                Text(individual
                    ? tr("LivePetIntake_Individual", "حيوان بهوية مستقلة")
                    : tr("LivePetIntake_Quantity", "مجموعة بكمية موحّدة"))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(selected ? .white : AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                Text(individual
                    ? tr("LivePetIntake_IndividualSub", "حلقة/شريحة وسعر لكل حيوان")
                    : tr("LivePetIntake_QuantitySub", "كمية وسعر وتكلفة مشتركة"))
                    .font(AdminType.caption)
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                selected ? AdminSurface.primary : AdminSurface.control,
                in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.isEditingLivePet)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Intake Roster
    //
    // The individual-intake surface is a *roster*, not a form list. Receiving a
    // batch of live animals is a repetitive reconciliation task, so the section
    // is built around three questions the operator asks continuously:
    //
    //   1. How many animals are still not ready to submit, and which ones?
    //   2. For the animal I am on, exactly what is missing?
    //   3. How do I get to the next animal without losing my place?
    //
    // `rosterCommandBar` answers (1) at a glance, the readiness dial on each
    // passport answers (2) without expanding it, and `advanceToNextUnit`
    // answers (3). Every animal keeps its own identity, gender, price, cost,
    // date, supplier and notes; nothing here invents state the Infra unit
    // contract does not own.

    @ViewBuilder
    private var individualIntake: some View {
        if viewModel.isEditingLivePet {
            operationalCallout(
                title: tr("LivePetIntake_UnitsManagedElsewhere", "السجلات الفردية محمية"),
                message: tr("LivePetIntake_UnitsManagedElsewhereSub", "هذا المحرر يغيّر السعر القياسي وبيانات الكتالوج فقط. حالات الحيوانات وحركاتها تُدار من مساحة المخزون."),
                symbol: "lock.doc.fill",
                color: Color(uiColor: .ppInfo)
            )
        } else {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                rosterCommandBar

                VStack(spacing: AdminSpacing.sm) {
                    ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { index, unit in
                        unitPassport(
                            index: index,
                            unit: unit,
                            binding: $viewModel.livePetUnits[index]
                        )
                    }
                }

                addAnimalControl
            }
        }
    }

    // MARK: Roster command bar

    /// Header, readiness ledger and the jump strip.
    ///
    /// The readiness numbers are derived, never stored: a second source of truth
    /// for "is this animal ready" would drift from `validate()` immediately.
    private var rosterCommandBar: some View {
        let total = viewModel.livePetUnits.count
        let readyCount = viewModel.livePetUnits.filter { unitReadiness(for: $0).isSubmittable }.count
        let blocked = total - readyCount

        return VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(tr("LivePetIntake_AnimalPassports", "جوازات الإدخال"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(tr("LivePetIntake_RosterSub", "كل حيوان سجل مستقل بهويته وجنسه وسعره. أكمل الناقص ثم انتقل للحيوان التالي."))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AdminSpacing.xs)

                // Ready / total, with the numerals forced LTR so "3/12" never
                // reverses inside an Arabic layout.
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 1) {
                        Text(verbatim: readyCount.englishDigits)
                            .font(PPBrandFont.bold(size: 22))
                            .foregroundStyle(blocked == 0 ? Color(uiColor: .ppSuccess) : AdminSurface.primaryText)
                        Text(verbatim: "/\(total.englishDigits)")
                            .font(PPBrandFont.bold(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.top, 5)
                    }
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)

                    Text(tr("LivePetIntake_ReadyLabel", "جاهز للإرسال"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(
                    format: tr("LivePetIntake_ReadyAccessibility", "%1$ld من %2$ld حيوانات جاهزة للإرسال"),
                    readyCount,
                    total
                ))
            }

            rosterProgressRail(readyCount: readyCount, total: total)

            if total > 1 {
                rosterJumpStrip
            }

            if blocked > 0 {
                Label(
                    String(format: tr("LivePetIntake_BlockedCount", "%ld حيوانات تنتظر بيانات ناقصة"), blocked).normalizedEnglishDigits,
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(AdminType.caption)
                .foregroundStyle(Color(uiColor: .ppWarning))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AdminSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    /// One decorative segment per animal, so progress is spatial rather than a
    /// single averaged bar. Hidden from VoiceOver because the numeric ledger
    /// above already carries the same fact.
    private func rosterProgressRail(readyCount: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { _, unit in
                let readiness = unitReadiness(for: unit)
                Capsule(style: .continuous)
                    .fill(readiness.isSubmittable ? readiness.tint : readiness.tint.opacity(0.34))
                    .frame(height: 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(readiness.tint.opacity(0.55), lineWidth: 0.5)
                    )
            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.2), value: readyCount)
        .accessibilityHidden(true)
    }

    /// Horizontal jump strip. Each chip is a real 44pt control that both reports
    /// one animal's readiness and moves the roster to it.
    private var rosterJumpStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AdminSpacing.xs) {
                ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { index, unit in
                    let readiness = unitReadiness(for: unit)
                    let active = expandedUnitID == unit.id
                    Button {
                        setExpandedUnit(active ? nil : unit.id)
                    } label: {
                        Text(verbatim: (index + 1).englishDigits)
                            .font(PPBrandFont.bold(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(active ? .white : readiness.tint)
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                            .background(
                                Circle().fill(active ? readiness.tint : readiness.tint.opacity(0.12))
                            )
                            .overlay(
                                Circle().strokeBorder(readiness.tint.opacity(active ? 0 : 0.42), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                    .accessibilityLabel(String(
                        format: tr("LivePetIntake_JumpAccessibility", "الحيوان %ld، %@"),
                        index + 1,
                        readiness.statusSummary
                    ))
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityHint(tr("LivePetIntake_JumpHint", "ينتقل إلى جواز هذا الحيوان"))
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
        .frame(height: AdminTouchTarget.minimum + 2)
    }

    private var addAnimalControl: some View {
        let count = viewModel.livePetUnits.count
        let atCapacity = count >= 100

        return Button {
            viewModel.addLivePetUnit()
            setExpandedUnit(viewModel.livePetUnits.last?.id)
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(tr("LivePetIntake_AddAnimal", "إضافة حيوان آخر"))
                    .font(AdminType.calloutBold)
                Spacer(minLength: AdminSpacing.xs)
                Text(verbatim: "\(count.englishDigits)/100")
                    .font(PPBrandFont.bold(size: 12))
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .foregroundStyle(atCapacity ? AdminSurface.secondaryText : AdminSurface.primary)
            .padding(.horizontal, AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
            .background(
                (atCapacity ? AdminSurface.control : AdminSurface.primary.opacity(0.09)),
                in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    .strokeBorder(
                        (atCapacity ? AdminSurface.hairline : AdminSurface.primary.opacity(0.30)),
                        style: StrokeStyle(lineWidth: 1, dash: atCapacity ? [] : [5, 4])
                    )
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(atCapacity)
        .accessibilityHint(atCapacity
            ? tr("LivePetIntake_AddAnimalCapacity", "بلغت الحد الأقصى 100 حيوان في الإدخال الواحد")
            : tr("LivePetIntake_AddAnimalHint", "ينشئ جواز إدخال فارغاً جديداً"))
    }

    // MARK: Readiness model

    private func unitReadiness(for unit: PPLivePetUnitDraft) -> PPUnitReadiness {
        let ring = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRing = !ring.isEmpty
        let hasPrice = isPositiveMoney(unit.sellingPriceText)
        let costRequired = viewModel.canViewStockCosts
        let hasCost = !costRequired || isNonNegativeMoney(unit.purchaseCostText)

        var missing: [String] = []
        if !hasRing { missing.append(tr("LivePetIntake_MissingIdentity", "الهوية")) }
        if !hasPrice { missing.append(tr("LivePetIntake_MissingPrice", "سعر البيع")) }
        if costRequired && !hasCost { missing.append(tr("LivePetIntake_MissingCost", "تكلفة الاستلام")) }

        let required = costRequired ? 3 : 2
        let satisfied = [hasRing, hasPrice, hasCost].filter { $0 }.count - (costRequired ? 0 : 1)
        let duplicate = hasRing && viewModel.duplicateRingTagKeys.contains(
            PPAccessoryEditorViewModel.ringTagKey(unit.ringTag)
        )
        let untouched = !hasRing && !hasPrice && unit.purchaseCostText.isEmpty
            && unit.supplier.isEmpty && unit.notes.isEmpty && unit.gender == .unspecified

        let tint: Color
        let summary: String
        if duplicate {
            tint = Color(uiColor: .ppError)
            summary = tr("LivePetIntake_StatusDuplicate", "هوية مكررة")
        } else if satisfied == required {
            tint = Color(uiColor: .ppSuccess)
            summary = tr("LivePetIntake_StatusReady", "مكتمل")
        } else if untouched {
            tint = Color(uiColor: .ppTextTertiary)
            summary = tr("LivePetIntake_StatusEmpty", "فارغ")
        } else {
            tint = Color(uiColor: .ppWarning)
            summary = tr("LivePetIntake_StatusPartial", "غير مكتمل")
        }

        return PPUnitReadiness(
            satisfied: max(0, satisfied),
            required: required,
            missingLabels: missing,
            isDuplicateIdentity: duplicate,
            isUntouched: untouched,
            genderRecorded: unit.gender != .unspecified,
            statusSummary: summary,
            tint: tint
        )
    }

    private func isPositiveMoney(_ raw: String) -> Bool {
        let clean = raw.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(clean), value > 0, value <= 999_999_999.99 else { return false }
        return abs(value * 100 - (value * 100).rounded()) < 0.000_001
    }

    private func isNonNegativeMoney(_ raw: String) -> Bool {
        let clean = raw.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let value = Double(clean), value >= 0, value <= 999_999_999.99 else { return false }
        return abs(value * 100 - (value * 100).rounded()) < 0.000_001
    }

    // MARK: Passport

    private func unitPassport(
        index: Int,
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>
    ) -> some View {
        let expanded = expandedUnitID == unit.id
        let readiness = unitReadiness(for: unit)
        let photo = viewModel.livePetUnitPhoto(for: unit.id)

        return VStack(spacing: 0) {
            passportSpine(
                index: index,
                unit: unit,
                readiness: readiness,
                expanded: expanded,
                photo: photo
            )

            if expanded {
                Rectangle()
                    .fill(AdminSurface.hairline.opacity(0.72))
                    .frame(height: 0.75)

                passportBody(index: index, unit: unit, binding: binding, readiness: readiness)
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(
                    expanded
                        ? readiness.tint.opacity(0.54)
                        : (readiness.isSubmittable ? AdminSurface.hairline : readiness.tint.opacity(0.42)),
                    lineWidth: expanded ? 1.25 : (readiness.isSubmittable ? 0.75 : 1)
                )
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(readiness.tint)
                .frame(width: 3)
                .padding(.vertical, AdminSpacing.md)
                .opacity(expanded ? 1 : 0.52)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .shadow(
            color: Color.black.opacity(expanded ? 0.065 : 0.025),
            radius: expanded ? 14 : 5,
            x: 0,
            y: expanded ? 6 : 2
        )
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22), value: expanded)
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.2), value: readiness.isSubmittable)
    }

    /// Collapsed decision row. The progress aperture becomes the animal's image
    /// when one exists, while preserving completion, identity, sex and price at
    /// a glance. Tapping it changes only expansion state.
    private func passportSpine(
        index: Int,
        unit: PPLivePetUnitDraft,
        readiness: PPUnitReadiness,
        expanded: Bool,
        photo: UIImage?
    ) -> some View {
        let ring = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            setExpandedUnit(expanded ? nil : unit.id)
        } label: {
            HStack(alignment: .center, spacing: AdminSpacing.md) {
                passportIdentityAperture(
                    index: index,
                    readiness: readiness,
                    photo: photo
                )

                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    HStack(spacing: AdminSpacing.xs) {
                        readinessStatusPill(readiness)
                        if photo != nil {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                                .accessibilityHidden(true)
                        }
                    }

                    Text(ring.isEmpty ? tr("LivePetIntake_IdentifierMissing", "الهوية مطلوبة") : ring.normalizedEnglishDigits)
                        .font(ring.isEmpty
                            ? AdminType.calloutBold
                            : PPBrandFont.bold(size: 16))
                        .foregroundStyle(ring.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                        .environment(\.layoutDirection, ring.isEmpty && Language.isRTL() ? .rightToLeft : .leftToRight)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: AdminSpacing.xs) {
                        genderTag(unit.gender)

                        if isPositiveMoney(unit.sellingPriceText) {
                            Text(verbatim: String(
                                format: tr("LivePetIntake_UnitPriceFormat", "%@ ر.ق"),
                                unit.sellingPriceText.normalizedEnglishDigits
                            ))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    if !readiness.isSubmittable {
                        Text(readiness.isDuplicateIdentity
                            ? tr("LivePetIntake_DuplicateIdentity", "هذه الهوية مستخدمة في حيوان آخر")
                            : String(
                                format: tr("LivePetIntake_MissingFormat", "ناقص: %@"),
                                readiness.missingLabels.joined(separator: tr("ListSeparator", "، "))
                            ))
                            .font(AdminType.caption2)
                            .foregroundStyle(readiness.tint)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: AdminSpacing.xs)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
            }
            .padding(AdminSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: tr("LivePetIntake_PassportAccessibility", "جواز الحيوان %1$ld، %2$@، الجنس %3$@، %4$@"),
            index + 1,
            ring.isEmpty ? tr("LivePetIntake_IdentifierMissing", "الهوية مطلوبة") : ring,
            unit.gender.localizedTitle,
            readiness.statusSummary
        ))
        .accessibilityValue(expanded ? tr("LivePetIntake_Expanded", "مفتوح") : tr("LivePetIntake_Collapsed", "مطوي"))
        .accessibilityHint(expanded
            ? tr("LivePetIntake_CollapseHint", "يطوي تفاصيل الجواز")
            : tr("LivePetIntake_ExpandHint", "يفتح تفاصيل الجواز"))
        .accessibilityAddTraits(.isButton)
    }

    /// A photo-aware completion aperture. The ring remains the authoritative
    /// readiness signal; the image is identity context, never completion proof.
    private func passportIdentityAperture(
        index: Int,
        readiness: PPUnitReadiness,
        photo: UIImage?
    ) -> some View {
        ZStack {
            Circle()
                .fill(readiness.tint.opacity(0.09))

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else if readiness.isDuplicateIdentity {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(readiness.tint)
            } else if readiness.isSubmittable {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(readiness.tint)
                    .transition(.opacity)
            } else {
                Text(verbatim: String(format: "%02d", index + 1).normalizedEnglishDigits)
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }

            Circle()
                .strokeBorder(AdminSurface.hairline, lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: max(0.001, readiness.progress))
                .stroke(readiness.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.28), value: readiness.progress)
        }
        .frame(width: 52, height: 52)
        .overlay(alignment: .bottomTrailing) {
            if photo != nil {
                Text(verbatim: (index + 1).englishDigits)
                    .font(PPBrandFont.bold(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(readiness.tint, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.surface, lineWidth: 2))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .accessibilityHidden(true)
    }

    private func readinessStatusPill(_ readiness: PPUnitReadiness) -> some View {
        let symbol: String
        if readiness.isDuplicateIdentity {
            symbol = "exclamationmark.triangle.fill"
        } else if readiness.isSubmittable {
            symbol = "checkmark.circle.fill"
        } else if readiness.isUntouched {
            symbol = "circle.dashed"
        } else {
            symbol = "circle.lefthalf.filled"
        }

        return Label(readiness.statusSummary, systemImage: symbol)
            .font(AdminType.caption2Bold)
            .foregroundStyle(readiness.tint)
            .padding(.horizontal, AdminSpacing.xs)
            .padding(.vertical, 3)
            .background(readiness.tint.opacity(0.10), in: Capsule(style: .continuous))
    }

    /// Compact gender pill for the collapsed row. Absent gender is stated
    /// explicitly rather than omitted, so a missing biological record is visible
    /// without opening the passport.
    private func genderTag(_ gender: PPLivePetUnitGender) -> some View {
        let tint = Color(uiColor: gender.tint)
        return HStack(spacing: 3) {
            Image(systemName: gender.symbolName)
                .font(.system(size: 9, weight: .bold))
            Text(gender.localizedShortTitle)
                .font(AdminType.caption2Bold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AdminSpacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 0.5))
    }

    // MARK: Passport body

    private func passportBody(
        index: Int,
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 01 Identity & Gender
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 1,
                    symbol: "viewfinder.circle.fill",
                    title: tr("LivePetIntake_PassportIdentityTitle", "إشارة الهوية")
                )

                identityCaptureLayout(unit: unit, binding: binding, readiness: readiness)
                unitGenderSelector(unit: unit)
            }

            passportSectionDivider

            // 02 Commercial
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 2,
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: tr("LivePetIntake_PassportCommercialTitle", "الإحداثيات التجارية")
                )
                moneyFields(unit: unit, binding: binding)
            }

            passportSectionDivider

            // 03 Provenance & Arrival Context (Side-by-side date & supplier, notes below)
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 3,
                    symbol: "clock.arrow.circlepath",
                    title: tr("LivePetIntake_PassportProvenanceTitle", "سياق الوصول")
                )

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        receivedDateField(binding: binding)
                        supplierField(unit: unit, binding: binding)
                    }
                } else {
                    HStack(alignment: .top, spacing: AdminSpacing.sm) {
                        receivedDateField(binding: binding)
                        supplierField(unit: unit, binding: binding)
                    }
                }

                notesField(unit: unit, binding: binding)
            }

            passportActions(index: index, unit: unit)
        }
        .padding(AdminSpacing.md)
        .background(
            LinearGradient(
                colors: [readiness.tint.opacity(0.045), AdminSurface.primaryText.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .transition(
            accessibilityReduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                )
        )
    }

    private func supplierField(unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: tr("LivePetIntake_SupplierField", "المورد أو المصدر"),
            symbol: "shippingbox.fill",
            required: false,
            optionalNote: tr("LivePetIntake_Optional", "اختياري"),
            focused: focusedField == .unitSupplier(unit.id)
        ) {
            TextField(
                "",
                text: binding.supplier,
                prompt: promptText(tr("LivePetIntake_SupplierPrompt", "اسم المورد أو المزرعة"))
            )
            .font(AdminType.body)
            .foregroundStyle(AdminSurface.primaryText)
            .focused($focusedField, equals: .unitSupplier(unit.id))
            .submitLabel(.next)
            .onSubmit { focusedField = .unitNotes(unit.id) }
            .accessibilityLabel(tr("LivePetIntake_SupplierField", "المورد أو المصدر"))
        }
    }

    private func notesField(unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: tr("LivePetIntake_NotesField", "ملاحظات الاستلام الداخلية"),
            symbol: "text.alignleft",
            required: false,
            optionalNote: tr("LivePetIntake_Optional", "اختياري"),
            focused: focusedField == .unitNotes(unit.id)
        ) {
            TextField(
                "",
                text: binding.notes,
                prompt: promptText(tr("LivePetIntake_NotesPrompt", "حالة الوصول، ملاحظة بيطرية، أي تحفظ"))
            )
            .font(AdminType.body)
            .foregroundStyle(AdminSurface.primaryText)
            .focused($focusedField, equals: .unitNotes(unit.id))
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityLabel(tr("LivePetIntake_NotesField", "ملاحظات الاستلام الداخلية"))
        }
    }

    @ViewBuilder
    private func identityCaptureLayout(
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                unitPhotoCard(unit: unit)
                identityFieldsColumn(unit: unit, binding: binding, readiness: readiness)
            }
        } else {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                unitPhotoCard(unit: unit)
                    .frame(width: 104)
                identityFieldsColumn(unit: unit, binding: binding, readiness: readiness)
            }
        }
    }

    @ViewBuilder
    private func identityFieldsColumn(
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            identityField(unit: unit, binding: binding, readiness: readiness)

            if viewModel.hasSubSubKinds {
                unitSubSubKindSelector(unit: unit)
            }

            if let subSubID = unit.subSubKindID,
               let items = viewModel.subSubKindItemsBySubSubID[subSubID],
               !items.isEmpty {
                unitSubSubKindItemSelector(unit: unit, items: items)
            }
        }
    }

    private func unitSubSubKindSelector(unit: PPLivePetUnitDraft) -> some View {
        let selectedSubSub = viewModel.availableSubSubKinds.first { $0.numericID == unit.subSubKindID }
        let title = selectedSubSub?.localizedName ?? tr("LivePetIntake_SelectSubSubKind", "اختر التفريع الفرعي...")
        let hasSelection = selectedSubSub != nil

        return intakeField(
            caption: tr("LivePetIntake_SubSubKindLabel", "التفريع الفرعي (SubSubKind)"),
            symbol: "arrow.triangle.branch",
            required: false,
            optionalNote: tr("LivePetIntake_Optional", "اختياري"),
            focused: false
        ) {
            Menu {
                Button {
                    viewModel.setLivePetUnitSubSubKind(nil, unitID: unit.id)
                } label: {
                    Label(tr("LivePetIntake_None", "بدون تفريع"), systemImage: "xmark")
                }
                Divider()
                ForEach(viewModel.availableSubSubKinds) { subSub in
                    Button {
                        viewModel.setLivePetUnitSubSubKind(subSub, unitID: unit.id)
                    } label: {
                        HStack {
                            Text(subSub.localizedName)
                            if unit.subSubKindID == subSub.numericID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AdminSpacing.xs) {
                    Text(title)
                        .font(AdminType.body)
                        .foregroundStyle(hasSelection ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func unitSubSubKindItemSelector(unit: PPLivePetUnitDraft, items: [AdminSubKindItemDetail]) -> some View {
        let selectedItem = items.first { $0.numericID == unit.subSubKindItemID }
        let title = selectedItem?.localizedName ?? tr("LivePetIntake_SelectSubSubKindItem", "اختر تصنيف العنصر...")
        let hasSelection = selectedItem != nil

        return intakeField(
            caption: tr("LivePetIntake_SubSubKindItemLabel", "عنصر التفريع (SubSubKindItem)"),
            symbol: "tag.fill",
            required: false,
            optionalNote: tr("LivePetIntake_Optional", "اختياري"),
            focused: false
        ) {
            Menu {
                Button {
                    viewModel.setLivePetUnitSubSubKindItem(nil, unitID: unit.id)
                } label: {
                    Label(tr("LivePetIntake_None", "بدون عنصر"), systemImage: "xmark")
                }
                Divider()
                ForEach(items) { item in
                    Button {
                        viewModel.setLivePetUnitSubSubKindItem(item, unitID: unit.id)
                    } label: {
                        HStack {
                            Text(item.localizedName)
                            if unit.subSubKindItemID == item.numericID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AdminSpacing.xs) {
                    Text(title)
                        .font(AdminType.body)
                        .foregroundStyle(hasSelection ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func unitPhotoCard(unit: PPLivePetUnitDraft) -> some View {
        let photo = viewModel.livePetUnitPhoto(for: unit.id)
        let canAttach = viewModel.canManageStock

        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if let photo {
                        previewMedia = PPLivePetPreviewMedia(source: .local(photo))
                    } else {
                        presentUnitPhotoSource(for: unit.id)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(photo == nil ? AdminSurface.primary.opacity(0.055) : AdminSurface.control)

                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.44)],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            Label(
                                tr("LivePetIntake_UnitPhotoPreview", "معاينة"),
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(.white)
                            .padding(AdminSpacing.xs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: canAttach ? "camera.aperture" : "lock.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(canAttach ? AdminSurface.primary : AdminSurface.secondaryText)
                                Text(tr("LivePetIntake_UnitPhotoAdd", "أضف صورة"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(tr("LivePetIntake_Optional", "اختياري"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .multilineTextAlignment(.center)
                            .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 130 : 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                photo == nil ? AdminSurface.primary.opacity(0.30) : AdminSurface.hairline,
                                style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [4, 3] : [])
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                .disabled(!canAttach && photo == nil)
                .accessibilityLabel(photo == nil
                    ? tr("LivePetIntake_UnitPhotoAddAccessibility", "إضافة صورة لهذا الحيوان")
                    : tr("LivePetIntake_UnitPhotoPreviewAccessibility", "معاينة صورة هذا الحيوان"))
                .accessibilityHint(photo == nil
                    ? tr("LivePetIntake_UnitPhotoAddHint", "يفتح الكاميرا أو مكتبة الصور")
                    : tr("LivePetIntake_UnitPhotoPreviewHint", "يفتح الصورة بملء الشاشة"))

                if photo != nil {
                    Button(role: .destructive) {
                        viewModel.removeLivePetUnitPhoto(unitID: unit.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .accessibilityLabel(tr("LivePetIntake_UnitPhotoRemove", "إزالة صورة هذا الحيوان"))
                    .accessibilityHint(tr("LivePetIntake_UnitPhotoRemoveHint", "يزيل الصورة المحلية قبل حفظ الإدخال"))
                }
            }

            Label(
                tr("LivePetIntake_UnitPhotoInternalNote", "ترتبط بسجل هذا الحيوان فقط"),
                systemImage: "link.badge.plus"
            )
            .font(.system(size: 9))
            .foregroundStyle(AdminSurface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private func passportSectionHeader(
        sequence: Int,
        symbol: String,
        title: String
    ) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.10))
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 22, height: 22)

            Text(verbatim: String(format: "%02d", sequence).normalizedEnglishDigits)
                .font(PPBrandFont.bold(size: 10))
                .foregroundStyle(AdminSurface.primary)
                .environment(\.layoutDirection, .leftToRight)

            Text(title)
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.primaryText)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var passportSectionDivider: some View {
        Rectangle()
            .fill(AdminSurface.hairline.opacity(0.50))
            .frame(height: 0.5)
            .padding(.vertical, 1)
            .accessibilityHidden(true)
    }

    private func identityField(
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        let ring = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)

        return intakeField(
            caption: tr("LivePetIntake_RingLabel", "رقم الحلقة أو الشريحة"),
            symbol: "number",
            required: true,
            focused: focusedField == .unitRing(unit.id),
            invalid: readiness.isDuplicateIdentity,
            footnote: readiness.isDuplicateIdentity
                ? tr("LivePetIntake_DuplicateIdentity", "هذه الهوية مستخدمة في حيوان آخر")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            HStack(spacing: AdminSpacing.xs) {
                TextField(
                    "",
                    text: binding.ringTag,
                    prompt: promptText("QA-RING-000")
                )
                .font(PPBrandFont.bold(size: 17))
                .foregroundStyle(AdminSurface.primaryText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textContentType(.none)
                .keyboardType(.asciiCapable)
                // A ring or microchip code is a technical identifier: it stays
                // LTR even in the Arabic layout so digits never reorder.
                .environment(\.layoutDirection, .leftToRight)
                .multilineTextAlignment(.leading)
                .focused($focusedField, equals: .unitRing(unit.id))
                .submitLabel(.next)
                .onSubmit { focusedField = .unitSellingPrice(unit.id) }
                .accessibilityLabel(tr("LivePetIntake_RingLabel", "رقم الحلقة أو الشريحة"))

                if !ring.isEmpty {
                    Button {
                        binding.ringTag.wrappedValue = ""
                        focusedField = .unitRing(unit.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(width: 30, height: AdminTouchTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("LivePetIntake_ClearIdentity", "مسح رقم الحلقة"))
                }

                AdminBarcodeScanButton { scanned in
                    binding.ringTag.wrappedValue = scanned
                    focusedField = nil
                }
            }
        }
    }

    @ViewBuilder
    private func moneyFields(unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AdminSpacing.base) {
                sellingPriceField(unit: unit, binding: binding)
                if viewModel.canViewStockCosts {
                    purchaseCostField(unit: unit, binding: binding)
                }
            }
        } else {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                sellingPriceField(unit: unit, binding: binding)
                if viewModel.canViewStockCosts {
                    purchaseCostField(unit: unit, binding: binding)
                }
            }
        }
    }

    private func sellingPriceField(unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        let entered = !unit.sellingPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return intakeField(
            caption: tr("LivePetIntake_UnitSellingPriceShort", "سعر البيع"),
            symbol: "tag.fill",
            required: true,
            focused: focusedField == .unitSellingPrice(unit.id),
            invalid: entered && !isPositiveMoney(unit.sellingPriceText),
            trailingAffix: tr("QAR", "ر.ق"),
            footnote: entered && !isPositiveMoney(unit.sellingPriceText)
                ? tr("LivePetIntake_MoneyFormat", "مبلغ صالح بمنزلتين عشريتين كحد أقصى")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            moneyTextField(
                text: binding.sellingPriceText,
                field: .unitSellingPrice(unit.id),
                label: tr("LivePetIntake_UnitSellingPrice", "سعر البيع (ر.ق)")
            )
        }
    }

    private func purchaseCostField(unit: PPLivePetUnitDraft, binding: Binding<PPLivePetUnitDraft>) -> some View {
        let entered = !unit.purchaseCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return intakeField(
            caption: tr("LivePetIntake_UnitCostShort", "تكلفة الاستلام"),
            symbol: "arrow.down.circle.fill",
            required: true,
            focused: focusedField == .unitPurchaseCost(unit.id),
            invalid: entered && !isNonNegativeMoney(unit.purchaseCostText),
            trailingAffix: tr("QAR", "ر.ق"),
            footnote: entered && !isNonNegativeMoney(unit.purchaseCostText)
                ? tr("LivePetIntake_MoneyFormat", "مبلغ صالح بمنزلتين عشريتين كحد أقصى")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            moneyTextField(
                text: binding.purchaseCostText,
                field: .unitPurchaseCost(unit.id),
                label: tr("LivePetIntake_UnitCost", "تكلفة الاستلام (ر.ق)")
            )
        }
    }

    private func moneyTextField(text: Binding<String>, field: FocusedField, label: String) -> some View {
        TextField("", text: text, prompt: promptText("0.00"))
            .font(PPBrandFont.bold(size: 18))
            .foregroundStyle(AdminSurface.primaryText)
            .englishNumericInput(text: text, allowsDecimal: true)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .focused($focusedField, equals: field)
            .accessibilityLabel(label)
    }

    private func receivedDateField(binding: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: tr("LivePetIntake_ReceivedDate", "تاريخ الاستلام"),
            symbol: "calendar",
            required: false,
            focused: false
        ) {
            DatePicker(
                tr("LivePetIntake_ReceivedDate", "تاريخ الاستلام"),
                selection: binding.acquisitionDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(AdminType.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Per-animal gender

    /// Gender is recorded **per animal**, not once for the catalog item, because
    /// each individually tracked unit is a distinct animal with its own
    /// biological record. Values map 1:1 onto the Infra `gender` enum; an
    /// untouched animal submits `UNSPECIFIED` rather than a guess.
    private func unitGenderSelector(unit: PPLivePetUnitDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                Image(systemName: "allergens.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(tr("LivePetIntake_UnitGender", "جنس هذا الحيوان"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer(minLength: AdminSpacing.xs)
                if unit.gender == .unspecified {
                    Text(tr("LivePetIntake_GenderUnsetNote", "سيُحفظ كغير محدد"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 3) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: false)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: true)
                        }
                    }
                }
            }
            .padding(3)
            .background(AdminSurface.primaryText.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AdminSurface.hairline.opacity(0.75), lineWidth: 0.75)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("LivePetIntake_UnitGender", "جنس هذا الحيوان"))
    }

    private func genderOption(
        _ option: PPLivePetUnitGender,
        unit: PPLivePetUnitDraft,
        compact: Bool
    ) -> some View {
        let selected = unit.gender == option
        let tint = Color(uiColor: option.tint)

        return Button {
            viewModel.setLivePetUnitGender(option, unitID: unit.id)
        } label: {
            Group {
                if compact {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 11, weight: .bold))
                        Text(option.localizedShortTitle)
                            .font(AdminType.caption2Bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(option.localizedTitle)
                            .font(AdminType.calloutBold)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .padding(.horizontal, AdminSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
                }
            }
            .foregroundStyle(selected ? tint : AdminSurface.primaryText)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AdminSurface.surface)
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .matchedGeometryEffect(id: unit.id, in: genderSelectionNamespace)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.50) : AdminSurface.hairline.opacity(0.4), lineWidth: selected ? 1.2 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .animation(
            accessibilityReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84),
            value: unit.gender
        )
        .accessibilityLabel(option.localizedTitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Passport actions

    private func passportActions(index: Int, unit: PPLivePetUnitDraft) -> some View {
        let hasNext = index + 1 < viewModel.livePetUnits.count

        return HStack(spacing: 8) {
            removeUnitButton(unit.id)
            cloneUnitButton(unit)

            if hasNext || viewModel.livePetUnits.count < 100 {
                Button {
                    advanceFromUnit(at: index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasNext ? "arrow.forward.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(hasNext
                            ? tr("LivePetIntake_NextAnimal", "الحيوان التالي")
                            : tr("LivePetIntake_AddAnimal", "إضافة حيوان آخر"))
                            .font(AdminType.captionBold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                .accessibilityHint(hasNext
                    ? tr("LivePetIntake_NextAnimalHint", "يطوي هذا الجواز ويفتح الجواز التالي")
                    : tr("LivePetIntake_AddAnimalHint", "ينشئ جواز إدخال فارغاً جديداً"))
            }
        }
        .padding(.top, 2)
    }

    /// Collapses the current passport and opens the next one, creating it only
    /// when the operator is at the end of the roster and capacity allows.
    private func advanceFromUnit(at index: Int) {
        focusedField = nil
        if index + 1 < viewModel.livePetUnits.count {
            let nextID = viewModel.livePetUnits[index + 1].id
            UISelectionFeedbackGenerator().selectionChanged()
            setExpandedUnit(nextID)
        } else {
            viewModel.addLivePetUnit()
            setExpandedUnit(viewModel.livePetUnits.last?.id)
        }
    }

    private func cloneUnitButton(_ unit: PPLivePetUnitDraft) -> some View {
        Button {
            viewModel.clonePreviousUnit(from: unit)
            setExpandedUnit(viewModel.livePetUnits.last?.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 11, weight: .semibold))
                Text(tr("LivePetIntake_Clone", "نسخ كحيوان جديد"))
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(uiColor: .ppSuccess))
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.livePetUnits.count >= 100)
        .accessibilityHint(tr("LivePetIntake_CloneHint", "ينشئ حيواناً جديداً بنفس البيانات مع ترقيم الحلقة تلقائياً"))
    }

    private func removeUnitButton(_ id: String) -> some View {
        let isOnlyAnimal = viewModel.livePetUnits.count <= 1

        return Button(role: .destructive) {
            showRemoveAnimalAlert(for: id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                Text(tr("LivePetIntake_Remove", "إزالة"))
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
            }
            .foregroundStyle(isOnlyAnimal ? AdminSurface.secondaryText : Color(uiColor: .ppError))
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(
                (isOnlyAnimal ? AdminSurface.hairline.opacity(0.25) : Color(uiColor: .ppError).opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isOnlyAnimal ? AdminSurface.hairline : Color(uiColor: .ppError).opacity(0.24),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(isOnlyAnimal)
        .accessibilityHint(isOnlyAnimal
            ? tr("LivePetIntake_RemoveBlockedHint", "لا يمكن إزالة الحيوان الوحيد في الإدخال")
            : tr("LivePetIntake_RemoveHint", "يزيل هذا الحيوان من الإدخال الحالي بعد التأكيد"))
    }

    // MARK: Field shell

    /// Every editable control in the roster is wrapped in this shell.
    ///
    /// The original passport relied on fill-only inputs, which disappeared when
    /// the field fill and the surrounding card resolved to near-identical
    /// values. Here the affordance is made unconditional: a caption that never
    /// disappears on typing, a leading glyph, a permanently drawn border that
    /// thickens and tints on focus, an explicit error state, and a trailing
    /// currency affix so the number never has to carry the unit.
    private func intakeField<Control: View>(
        caption: String,
        symbol: String,
        required: Bool,
        optionalNote: String? = nil,
        focused: Bool,
        invalid: Bool = false,
        trailingAffix: String? = nil,
        footnote: String? = nil,
        footnoteTint: Color = Color(uiColor: .ppError),
        @ViewBuilder control: () -> Control
    ) -> some View {
        let borderColor: Color = {
            if invalid { return Color(uiColor: .ppError) }
            if focused { return AdminSurface.primary }
            return AdminSurface.hairline
        }()
        let borderWidth: CGFloat = invalid ? 1.4 : (focused ? 1.6 : 1)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                Text(caption)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if required {
                    Circle()
                        .fill(Color(uiColor: .ppError))
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                } else if let optionalNote {
                    Text(optionalNote)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: AdminSpacing.xs) {
                control()
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())

                if let trailingAffix {
                    Text(trailingAffix)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(AdminSurface.primaryText.opacity(0.06), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: invalid)

            if let footnote {
                Label(footnote, systemImage: "exclamationmark.triangle.fill")
                    .font(AdminType.caption2)
                    .foregroundStyle(footnoteTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Placeholders are rendered at a readable weight instead of the system
    /// default, which was one of the reasons the original fields looked empty.
    private func promptText(_ value: String) -> Text {
        Text(value).foregroundColor(AdminSurface.secondaryText.opacity(0.75))
    }

    private var quantityIntake: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            fieldLabel(tr("LivePetIntake_QuantityLabel", "عدد الحيوانات في المجموعة"), required: true)

            HStack(spacing: AdminSpacing.md) {
                quantityButton(symbol: "minus", enabled: viewModel.quantity > 1) {
                    viewModel.quantity = max(1, viewModel.quantity - 1)
                }

                Text(verbatim: viewModel.quantity.englishDigits)
                    .font(PPBrandFont.bold(size: 30))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String(
                        format: tr("LivePetIntake_QuantityAccessibility", "الكمية %ld"),
                        viewModel.quantity
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptQuantityEdit()
                    }

                quantityButton(symbol: "plus", enabled: true) {
                    viewModel.quantity += 1
                }
            }
            .padding(AdminSpacing.sm)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

            if viewModel.canViewStockCosts {
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("LivePetIntake_GroupCost", "تكلفة الحيوان الواحد (ر.ق)"), required: true)
                    TextField("0.00", text: $viewModel.liveGroupCostText)
                        .font(PPBrandFont.bold(size: 17))
                        .englishNumericInput(text: $viewModel.liveGroupCostText, allowsDecimal: true)
                        .focused($focusedField, equals: .groupCost)
                        .padding(.horizontal, AdminSpacing.md)
                        .frame(minHeight: AdminTouchTarget.expanded)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                }
            }

            DatePicker(
                tr("LivePetIntake_ReceivedDate", "تاريخ الاستلام"),
                selection: $viewModel.liveArrivalDate,
                displayedComponents: .date
            )
            .font(AdminType.callout)
            .frame(minHeight: AdminTouchTarget.minimum)

            TextField(tr("LivePetIntake_SupplierPlaceholder", "المورد أو المصدر (اختياري)"), text: $viewModel.liveSupplier)
                .font(AdminType.body)
                .focused($focusedField, equals: .supplier)
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))

            TextField(tr("LivePetIntake_GroupNotesPlaceholder", "ملاحظات إدخال المجموعة (اختيارية)"), text: $viewModel.liveIntakeNotes)
                .font(AdminType.body)
                .focused($focusedField, equals: .notes)
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
    }

    private func quantityButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? AdminSurface.primary : AdminSurface.secondaryText)
                .frame(width: AdminTouchTarget.expanded, height: AdminTouchTarget.expanded)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus"
            ? tr("LivePetIntake_IncreaseQuantity", "زيادة الكمية")
            : tr("LivePetIntake_DecreaseQuantity", "تقليل الكمية"))
    }

    private var previewNotes: some View {
        DisclosureGroup(isExpanded: $previewNotesExpanded) {
            VStack(spacing: AdminSpacing.md) {
                operationalCallout(
                    title: tr("LivePetIntake_PreviewOnly", "ملاحظات معاينة فقط"),
                    message: tr("LivePetIntake_PreviewOnlySub", "الجنس ومؤشرات الرعاية التالية تغيّر ملخص هذه الشاشة فقط؛ العقد الحالي لا يحفظها في سجل المخزون أو السجل الطبي."),
                    symbol: "eye.trianglebadge.exclamationmark",
                    color: Color(uiColor: .ppWarning)
                )

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("LivePetIntake_Gender", "الجنس الظاهر في المعاينة"), required: false)
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: AdminSpacing.sm) {
                                previewGenderButton(id: "male", title: tr("LivePetIntake_Male", "ذكر"), symbol: "m.circle.fill")
                                previewGenderButton(id: "female", title: tr("LivePetIntake_Female", "أنثى"), symbol: "f.circle.fill")
                                previewGenderButton(id: "pair", title: tr("LivePetIntake_Pair", "زوج"), symbol: "person.2.circle.fill")
                            }
                        } else {
                            HStack(spacing: AdminSpacing.sm) {
                                previewGenderButton(id: "male", title: tr("LivePetIntake_Male", "ذكر"), symbol: "m.circle.fill")
                                previewGenderButton(id: "female", title: tr("LivePetIntake_Female", "أنثى"), symbol: "f.circle.fill")
                                previewGenderButton(id: "pair", title: tr("LivePetIntake_Pair", "زوج"), symbol: "person.2.circle.fill")
                            }
                        }
                    }
                }

                VStack(spacing: AdminSpacing.sm) {
                    previewToggle(
                        title: tr("LivePetIntake_Vaccinated", "مطعّم"),
                        symbol: "cross.case.fill",
                        isOn: $viewModel.isVaccinated
                    )
                    previewToggle(
                        title: tr("LivePetIntake_Dewormed", "معالجة وقائية"),
                        symbol: "shield.checkered",
                        isOn: $viewModel.isDewormed
                    )
                    previewToggle(
                        title: tr("LivePetIntake_Microchipped", "شريحة إلكترونية"),
                        symbol: "cpu.fill",
                        isOn: $viewModel.isMicrochipped
                    )
                }
            }
            .padding(.top, AdminSpacing.md)
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(AdminSurface.primary)
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(tr("LivePetIntake_PreviewNotes", "ملاحظات المعاينة"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(tr("LivePetIntake_PreviewNotesSub", "اختيارية وغير محفوظة في السجل"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .accessibilityHint(previewNotesExpanded
            ? tr("LivePetIntake_CollapseHint", "يطوي التفاصيل")
            : tr("LivePetIntake_ExpandHint", "يفتح التفاصيل"))
    }

    private func previewGenderButton(id: String, title: String, symbol: String) -> some View {
        let selected = viewModel.selectedGender == id
        return Button {
            viewModel.selectedGender = id
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(title, systemImage: symbol)
                .font(AdminType.captionBold)
                .foregroundStyle(selected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                .background(selected ? AdminSurface.primary : AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func previewToggle(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.primaryText)
        }
        .tint(AdminSurface.primary)
        .frame(minHeight: AdminTouchTarget.minimum)
    }

    // MARK: Pricing

    private var pricingScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("LivePetIntake_PricingEyebrow", "قيمة واضحة"),
            title: tr("LivePetIntake_PricingTitle", "ثبّت السعر الذي سيظهر ويُحاسب به"),
            subtitle: viewModel.isIndividualLivePet
                ? tr("LivePetIntake_PricingIndividualSub", "السعر القياسي قيمة افتراضية؛ سعر كل حيوان في جواز الإدخال هو المرجع النهائي للبيع.")
                : tr("LivePetIntake_PricingQuantitySub", "حدد السعر الأساسي ثم أضف خصماً نسبياً أو مبلغاً ثابتاً عند الحاجة."),
            symbol: "q.circle.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                finalPricePlate

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(
                        viewModel.isIndividualLivePet
                            ? tr("LivePetIntake_StandardPrice", "السعر القياسي (ر.ق)")
                            : tr("LivePetIntake_BasePrice", "السعر الأساسي (ر.ق)"),
                        required: true
                    )
                    TextField("0.00", text: $viewModel.priceText)
                        .font(PPBrandFont.bold(size: 24))
                        .englishNumericInput(text: $viewModel.priceText, allowsDecimal: true)
                        .focused($focusedField, equals: .standardPrice)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, AdminSpacing.md)
                        .frame(minHeight: 64)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .standardPrice))
                }

                if viewModel.liveInventoryMode == .quantity {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: AdminSpacing.md) {
                                discountField(
                                    title: tr("LivePetIntake_DiscountPercent", "نسبة الخصم (%)"),
                                    text: $viewModel.discountPercentText,
                                    focus: .discountPercent
                                )
                                discountField(
                                    title: tr("LivePetIntake_DiscountAmount", "خصم ثابت (ر.ق)"),
                                    text: $viewModel.discountAmountText,
                                    focus: .discountAmount
                                )
                            }
                        } else {
                            HStack(spacing: AdminSpacing.sm) {
                                discountField(
                                    title: tr("LivePetIntake_DiscountPercent", "نسبة الخصم (%)"),
                                    text: $viewModel.discountPercentText,
                                    focus: .discountPercent
                                )
                                discountField(
                                    title: tr("LivePetIntake_DiscountAmount", "خصم ثابت (ر.ق)"),
                                    text: $viewModel.discountAmountText,
                                    focus: .discountAmount
                                )
                            }
                        }
                    }
                }

                if viewModel.liveInventoryMode == .quantity {
                    wholesaleCard
                    sellingUnitsCard
                }

                if viewModel.isIndividualLivePet && !viewModel.isEditingLivePet {
                    exactUnitPriceSummary
                }

                if let telemetry = viewModel.profitMarginTelemetry {
                    marginSummary(telemetry)
                }
            }
        }
    }

    private var finalPricePlate: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(viewModel.isIndividualLivePet
                        ? tr("LivePetIntake_CustomerUnitPrice", "سعر بيع الحيوان للعميل")
                        : tr("LivePetIntake_CustomerPrice", "السعر الظاهر للعميل"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(verbatim: viewModel.customerFacingPriceText.normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: dynamicTypeSize.isAccessibilitySize ? 28 : 36))
                        .foregroundStyle(AdminSurface.primary)
                        .environment(\.layoutDirection, .leftToRight)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                Image(systemName: viewModel.customerFacingPriceIsResolved ? "checkmark.seal.fill" : "ellipsis.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(viewModel.customerFacingPriceIsResolved ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
            }

            if viewModel.liveInventoryMode == .quantity,
               viewModel.calculatedFinalPrice < viewModel.basePrice,
               viewModel.basePrice > 0 {
                Text(verbatim: String(
                    format: tr("LivePetIntake_SavingsFormat", "وفر العميل %.2f ر.ق"),
                    viewModel.basePrice - viewModel.calculatedFinalPrice
                ).normalizedEnglishDigits)
                .font(AdminType.captionBold)
                .foregroundStyle(Color(uiColor: .ppSuccess))
            }
        }
        .padding(AdminSpacing.base)
        .background(
            LinearGradient(
                colors: [AdminSurface.primary.opacity(0.13), AdminSurface.primary.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func discountField(title: String, text: Binding<String>, focus: FocusedField) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(title, required: false)
            TextField("0", text: text)
                .font(PPBrandFont.bold(size: 18))
                .englishNumericInput(text: text, allowsDecimal: true)
                .focused($focusedField, equals: focus)
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exactUnitPriceSummary: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                Text(tr("LivePetIntake_ExactPrices", "أسعار الحيوانات الفردية"))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text(verbatim: viewModel.livePetUnits.count.englishDigits)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }

            ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { index, unit in
                HStack(spacing: AdminSpacing.sm) {
                    Text(verbatim: String(format: "%02d", index + 1).normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(unit.ringTag.isEmpty
                        ? tr("LivePetIntake_IdentifierMissing", "الهوية مطلوبة")
                        : unit.ringTag.normalizedEnglishDigits)
                        .font(unit.ringTag.isEmpty ? AdminType.caption : PPBrandFont.medium(size: 13))
                        .foregroundStyle(unit.ringTag.isEmpty ? Color(uiColor: .ppWarning) : AdminSurface.primaryText)
                        .environment(\.layoutDirection, unit.ringTag.isEmpty && Language.isRTL() ? .rightToLeft : .leftToRight)
                        .lineLimit(1)
                    Spacer()
                    Text(unit.sellingPriceText.isEmpty
                        ? "—"
                        : String(format: tr("LivePetIntake_UnitPriceFormat", "%@ ر.ق"), unit.sellingPriceText.normalizedEnglishDigits))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .frame(minHeight: 36)
                if index < viewModel.livePetUnits.count - 1 {
                    Divider().background(AdminSurface.hairline.opacity(0.7))
                }
            }

            Label(
                tr("LivePetIntake_ExactPriceAuthority", "عند البيع، سعر الحيوان الفردي يتقدم على السعر القياسي."),
                systemImage: "info.circle"
            )
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
    }

    private func marginSummary(_ telemetry: (marginPercent: Double, netProfit: Double)) -> some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(uiColor: .ppSuccess))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .ppSuccess).opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                Text(tr("LivePetIntake_Margin", "الهامش المتوقع"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(verbatim: String(format: "%.1f%%  •  +%.2f %@", telemetry.marginPercent, telemetry.netProfit, tr("QAR", "ر.ق")).normalizedEnglishDigits)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
        }
        .padding(AdminSpacing.md)
        .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var wholesaleCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Toggle(isOn: $viewModel.wholesaleEnabled.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                HStack(spacing: AdminSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .systemTeal).opacity(viewModel.wholesaleEnabled ? 0.18 : 0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal) : AdminSurface.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Wholesale_Selling_Title", "البيع بالجملة (Wholesale)"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(viewModel.wholesaleEnabled
                            ? tr("Wholesale_Active_Hint", "مفعل ومتاح في نقطة البيع للموزعين والعملاء بالجملة")
                            : tr("Wholesale_Inactive_Hint", "غير مفعل (قم بالتشغيل لتحديد سعر الجملة)"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .tint(Color(uiColor: .systemTeal))

            if viewModel.wholesaleEnabled {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    fieldLabel(tr("Wholesale_Price_QAR", "سعر بيع الجملة للوحدة الافتراضية (ر.ق)"), required: true)

                    TextField("0.00", text: $viewModel.wholesalePriceText)
                        .font(PPBrandFont.bold(size: 18))
                        .englishNumericInput(text: $viewModel.wholesalePriceText, allowsDecimal: true)
                        .focused($focusedField, equals: .wholesalePrice)
                        .padding(AdminSpacing.md)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .wholesalePrice))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal).opacity(0.35) : AdminSurface.hairline, lineWidth: 1)
        )
    }

    private var sellingUnitsCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                Label(tr("Selling_Units_Deck_Title", "وحدات ومجموعات البيع"), systemImage: "square.stack.3d.up.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Button {
                    let nextSort = viewModel.quantityGroups.count
                    let newGroup = PPQuantityGroupDraft(
                        id: "pack_\(nextSort + 1)_\(UUID().uuidString.prefix(4))",
                        nameAr: "",
                        nameEn: "",
                        unitsPerGroup: 6,
                        barcode: "",
                        sku: "",
                        sortOrder: nextSort,
                        retailEnabled: true,
                        wholesaleEnabled: viewModel.wholesaleEnabled,
                        retailPriceText: "",
                        wholesalePriceText: "",
                        defaultForRetail: false,
                        defaultForWholesale: false,
                        active: true
                    )
                    viewModel.selectedQuantityGroupForEditing = newGroup
                    viewModel.showQuantityGroupInspector = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(tr("Add_Selling_Unit", "إضافة وحدة"))
                    }
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }

            Text(tr("Selling_Units_Deck_Subtitle", "تحديد أحجام البيع (حبة، شدة، كرتون) مع خصم المخزون التلقائي بالوحدات الأساسية."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                ForEach(viewModel.quantityGroups) { group in
                    sellingUnitRow(for: group)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func sellingUnitRow(for group: PPQuantityGroupDraft) -> some View {
        Button {
            viewModel.selectedQuantityGroupForEditing = group
            viewModel.showQuantityGroupInspector = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(group.defaultForRetail ? AdminSurface.primary.opacity(0.15) : AdminSurface.control)
                        .frame(width: 38, height: 38)
                    Image(systemName: group.unitsPerGroup == 1 ? "cube.fill" : "shippingbox.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(group.defaultForRetail ? AdminSurface.primary : AdminSurface.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.localizedName)
                            .font(AdminType.bodyBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        if group.defaultForRetail {
                            Text(tr("Default_Retail_Badge", "افتراضي للتجزئة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                        if group.defaultForWholesale && group.wholesaleEnabled {
                            Text(tr("Default_Wholesale_Badge", "افتراضي للجملة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(uiColor: .systemTeal))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemTeal).opacity(0.12), in: Capsule())
                        }
                    }
                    Text(group.unitsCountText)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if group.retailEnabled {
                        Text(verbatim: String(format: "%.0f %@", group.retailPrice, tr("QAR", "ر.ق")).normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    if group.wholesaleEnabled {
                        Text(verbatim: String(format: tr("Wholesale_Price_Format", "جملة: %.0f ر.ق"), group.wholesalePrice).normalizedEnglishDigits)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(uiColor: .systemTeal))
                    }
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Release

    private var releaseScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("LivePetIntake_ReleaseEyebrow", "المراجعة والإتاحة"),
            title: tr("LivePetIntake_ReleaseTitle", "راجع الأثر ثم أطلق السجل"),
            subtitle: tr("LivePetIntake_ReleaseSubtitle", "اختر الفرع وحالة الظهور. سيبقى مسار المخزون والتدقيق تحت سلطة الخادم."),
            symbol: "checkmark.shield.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                catalogSnapshot
                branchSelector
                visibilitySelector
                readinessReview
                serverEffects
            }
        }
    }

    private var catalogSnapshot: some View {
        HStack(spacing: AdminSpacing.md) {
            snapshotImage
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tr("LivePetIntake_UnnamedPet", "حيوان بلا اسم بعد")
                    : viewModel.name)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)

                Text([viewModel.selectedMainKind?.kindName, viewModel.selectedSubKind?.subKindName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)

                Text(verbatim: viewModel.customerFacingPriceText.normalizedEnglishDigits)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primary)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 0)
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("LivePetIntake_CatalogSnapshot", "ملخص الكتالوج"))
    }

    @ViewBuilder
    private var snapshotImage: some View {
        Group {
            if let localImage = viewModel.firstLivePetPhoto {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipped()
            } else if let firstURL = viewModel.existingImageURLs.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? viewModel.firstLivePetUnitPhotoURL,
                      let url = URL(string: firstURL) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 88, height: 88)) {
                    mediaPlaceholder(symbol: "pawprint.fill")
                }
                .frame(width: 88, height: 88)
                .clipped()
            } else {
                mediaPlaceholder(symbol: "pawprint.fill")
            }
        }
        .frame(width: 88, height: 88)
        .clipped()
    }

    private var branchSelector: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("LivePetIntake_Branch", "الفرع المالك"), required: true)
            Button {
                viewModel.showStorePicker = true
            } label: {
                HStack(spacing: AdminSpacing.md) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 40, height: 40)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                        Text(viewModel.selectedStoreName)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                        Text(tr("LivePetIntake_BranchEffect", "يملك هذا الفرع المخزون والحركة الافتتاحية"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .accessibilityLabel("\(tr("LivePetIntake_Branch", "الفرع المالك"))، \(viewModel.selectedStoreName)")
            .accessibilityHint(tr("LivePetIntake_ChooseHint", "يفتح قائمة الاختيار"))
        }
    }

    private var visibilitySelector: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("LivePetIntake_Visibility", "حالة الظهور"), required: true)
            visibilityCard(
                draft: false,
                title: tr("LivePetIntake_PublishNow", "إتاحة الصنف في الكتالوج"),
                subtitle: tr("LivePetIntake_PublishNowSub", "يُحفظ السجل نشطاً مع طلب ظهوره في سوق التطبيق."),
                symbol: "eye.fill"
            )
            visibilityCard(
                draft: true,
                title: tr("LivePetIntake_SaveDraft", "حفظ كمسودة مخفية"),
                subtitle: tr("LivePetIntake_SaveDraftSub", "يُنشأ المخزون والتدقيق، بينما يبقى الصنف غير ظاهر للعملاء."),
                symbol: "eye.slash.fill"
            )
        }
    }

    private func visibilityCard(draft: Bool, title: String, subtitle: String, symbol: String) -> some View {
        let selected = viewModel.isDraft == draft
        return Button {
            viewModel.isDraft = draft
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : AdminSurface.primary)
                    .frame(width: 40, height: 40)
                    .background(selected ? AdminSurface.primary : AdminSurface.primary.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AdminSpacing.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? AdminSurface.primary : AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: selected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var readinessReview: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack {
                Text(tr("LivePetIntake_Readiness", "جاهزية السجل"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                let ready = firstIncompleteStage == nil
                Label(
                    ready ? tr("LivePetIntake_Ready", "جاهز") : tr("LivePetIntake_NeedsWork", "يحتاج استكمالاً"),
                    systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(AdminType.caption2Bold)
                .foregroundStyle(ready ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
            }

            readinessRow(
                title: tr("LivePetIntake_ReviewIdentity", "الاسم والنوع"),
                value: {
                    if let main = viewModel.selectedCategoryDisplayTitle, !main.isEmpty {
                        if let sub = viewModel.selectedSubCategoryDisplayTitle, !sub.isEmpty {
                            return "\(main) • \(sub)"
                        }
                        return main
                    }
                    return tr("LivePetIntake_NotComplete", "غير مكتمل")
                }(),
                complete: validationMessage(for: .identity) == nil,
                stage: .identity
            )
            readinessRow(
                title: tr("LivePetIntake_ReviewInventory", "المخزون"),
                value: viewModel.liveInventoryMode == .individual
                    ? String(format: tr("LivePetIntake_AnimalCount", "%ld حيوان"), viewModel.livePetUnits.count)
                    : String(format: tr("LivePetIntake_QuantityAccessibility", "الكمية %ld"), viewModel.quantity),
                complete: validationMessage(for: .bioVault) == nil,
                stage: .bioVault
            )
            readinessRow(
                title: tr("LivePetIntake_ReviewPrice", "السعر"),
                value: viewModel.customerFacingPriceText,
                complete: validationMessage(for: .pricing) == nil,
                stage: .pricing
            )
            readinessRow(
                title: tr("LivePetIntake_ReviewBranch", "الفرع والإتاحة"),
                value: viewModel.selectedStoreName,
                complete: validationMessage(for: .governance) == nil,
                stage: .governance
            )
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
    }

    private func readinessRow(title: String, value: String, complete: Bool, stage: PPEditorStage) -> some View {
        Button {
            move(to: stage)
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(complete ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(title)
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(value)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .frame(minHeight: AdminTouchTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)، \(value)")
        .accessibilityValue(complete ? tr("Complete", "مكتمل") : tr("LivePetIntake_NeedsWork", "يحتاج استكمالاً"))
    }

    private var serverEffects: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Text(tr("LivePetIntake_EffectsTitle", "ما الذي سيحدث عند الحفظ؟"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            effectRow(symbol: "square.grid.2x2.fill", text: tr("LivePetIntake_EffectCatalog", "إنشاء أو تحديث سجل الكتالوج العام."))
            effectRow(symbol: "number.square.fill", text: tr("LivePetIntake_EffectUnits", "إنشاء هويات الحيوانات الفردية المحمية عند اختيار التتبع الفردي."))
            effectRow(symbol: "arrow.left.arrow.right.circle.fill", text: tr("LivePetIntake_EffectMovement", "تسجيل حركة افتتاحية للمخزون."))
            effectRow(symbol: "checkmark.shield.fill", text: tr("LivePetIntake_EffectAudit", "تسجيل أثر تدقيق باسم الموظف المنفذ."))

            Label(
                tr("LivePetIntake_ProjectionNote", "إتاحة الكتالوج لا تنشئ إعلان Marketplace مستقلاً؛ إسقاط الإعلان له مسار خادم منفصل."),
                systemImage: "info.circle"
            )
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, AdminSpacing.xs)
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private func effectRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 24, height: 24)
            Text(text)
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var actionDock: some View {
        VStack(spacing: AdminSpacing.sm) {
            if let requirement = validationMessage(for: viewModel.activeStage),
               viewModel.activeStage != .governance {
                Label(requirement, systemImage: "circle.dashed")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.sm) {
                        primaryDockButton
                        if viewModel.activeStage.rawValue > 0 {
                            previousDockButton
                        }
                    }
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        if viewModel.activeStage.rawValue > 0 {
                            previousDockButton
                        }
                        primaryDockButton
                    }
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.sm)
        .padding(.bottom, AdminSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(AdminSurface.hairline.opacity(0.65))
        }
    }

    private var previousDockButton: some View {
        Button {
            guard let previous = PPEditorStage(rawValue: viewModel.activeStage.rawValue - 1) else { return }
            move(to: previous)
        } label: {
            Image(systemName: "arrow.backward")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : AdminTouchTarget.expanded)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.hasPendingLivePetRecovery)
        .accessibilityLabel(tr("LivePetIntake_Previous", "الخطوة السابقة"))
    }

    private var primaryDockButton: some View {
        Button {
            performPrimaryAction()
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: viewModel.hasPendingLivePetRecovery
                        ? "arrow.clockwise.icloud.fill"
                        : (viewModel.activeStage == .governance
                            ? (viewModel.isDraft ? "doc.badge.plus" : "checkmark.shield.fill")
                            : "arrow.forward"))
                        .font(.system(size: 16, weight: .bold))
                }
                Text(primaryActionTitle)
                    .font(AdminType.headline)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
            .padding(.horizontal, AdminSpacing.md)
            .background(
                LinearGradient(
                    colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
            )
            .shadow(color: AdminSurface.primary.opacity(accessibilityReduceMotion ? 0.12 : 0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.isSubmitting)
        .accessibilityHint(primaryActionHint)
    }

    private var primaryActionTitle: String {
        if viewModel.isAwaitingCatalogSync {
            return tr("LivePetIntake_RetryCatalogSync", "إعادة مزامنة الكتالوج")
        }
        if let failureAction = viewModel.submissionFailureActionTitle {
            return failureAction
        }
        if viewModel.hasPendingLivePetRecovery {
            return tr("LivePetIntake_ResumePendingOperation", "استئناف العملية المحفوظة")
        }
        if viewModel.activeStage != .governance {
            return tr("LivePetIntake_Continue", "متابعة")
        }
        if viewModel.editingAccessory != nil {
            return tr("LivePetIntake_SaveChanges", "حفظ التغييرات")
        }
        return viewModel.isDraft
            ? tr("LivePetIntake_CreateDraft", "إنشاء المسودة")
            : tr("LivePetIntake_RegisterVisible", "تسجيل وإتاحة الصنف")
    }

    private var primaryActionHint: String {
        if viewModel.isAwaitingCatalogSync {
            return tr("LivePetIntake_RetryCatalogSyncHint", "يعيد فقط مزامنة عرض الكتالوج بعد اعتماد عملية المخزون")
        }
        if viewModel.submissionFailureActionTitle != nil {
            return tr("LivePetIntake_SubmissionRecoveryHint", "ينفذ الإجراء الآمن المناسب لنتيجة الخادم الحالية")
        }
        if viewModel.hasPendingLivePetRecovery {
            return tr("LivePetIntake_ResumePendingOperationHint", "يعيد الطلب المحفوظ نفسه بمعرّف الأمر نفسه ثم يكمل مزامنة الكتالوج")
        }
        if viewModel.activeStage == .governance {
            return tr("LivePetIntake_SubmitHint", "يرسل العملية المصرح بها إلى الخادم ويمنع التكرار أثناء التنفيذ")
        }
        return tr("LivePetIntake_ContinueHint", "يتحقق من هذه الخطوة ثم ينتقل إلى التالية")
    }

    private func performPrimaryAction() {
        focusedField = nil
        if viewModel.submissionFailureKind != nil {
            stageMessage = nil
            viewModel.performSubmissionFailureAction()
            return
        }
        if viewModel.hasPendingLivePetRecovery {
            stageMessage = nil
            viewModel.saveAccessory()
            return
        }
        if viewModel.activeStage == .governance {
            guard let issue = firstIncompleteStage else {
                stageMessage = nil
                viewModel.saveAccessory()
                return
            }
            stageMessage = issue.message
            move(to: issue.stage, preservingMessage: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(notification: .announcement, argument: issue.message)
            return
        }

        if let message = validationMessage(for: viewModel.activeStage) {
            stageMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(notification: .announcement, argument: message)
            return
        }

        guard let next = PPEditorStage(rawValue: viewModel.activeStage.rawValue + 1) else { return }
        stageMessage = nil
        move(to: next)
    }

    private var submissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()
            VStack(spacing: AdminSpacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AdminSurface.primary)
                Text(tr("LivePetIntake_Submitting", "جارٍ حفظ السجل بأمان"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(tr("LivePetIntake_SubmittingSub", "قد تُرفع الصور ثم يُنشئ الخادم المخزون والحركة وسجل التدقيق. لا تغلق التطبيق."))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AdminSpacing.lg)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("LivePetIntake_Submitting", "جارٍ حفظ السجل بأمان"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilitySortPriority(100)
    }

    // MARK: Validation and helpers

    private var completedStageCount: Int {
        PPEditorStage.allCases.filter { validationMessage(for: $0) == nil }.count
    }

    private var firstIncompleteStage: (stage: PPEditorStage, message: String)? {
        for stage in PPEditorStage.allCases {
            if let message = validationMessage(for: stage) {
                return (stage, message)
            }
        }
        return nil
    }

    private func validationMessage(for stage: PPEditorStage) -> String? {
        switch stage {
        case .identity:
            let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                return tr("LivePetIntake_ValidationName", "أدخل اسماً واضحاً للحيوان أو الصنف.")
            }
            if trimmedName.utf16.count > 90 {
                return tr("LivePetIntake_ValidationNameLength", "يجب ألا يتجاوز الاسم 90 حرفاً.")
            }
            let trimmedNameEn = viewModel.nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNameEn.isEmpty && trimmedNameEn.utf16.count > 90 {
                return tr("LivePetIntake_ValidationNameLengthEn", "يجب ألا يتجاوز الاسم بالإنجليزية 90 حرفاً.")
            }
            if viewModel.desc.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 4_000 {
                return tr("LivePetIntake_ValidationDescriptionLength", "يجب ألا يتجاوز الوصف 4000 حرف.")
            }
            if viewModel.descEn.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 4_000 {
                return tr("LivePetIntake_ValidationDescriptionLengthEn", "يجب ألا يتجاوز الوصف بالإنجليزية 4000 حرف.")
            }
            if viewModel.selectedMainKind == nil {
                return tr("LivePetIntake_ValidationSpecies", "اختر نوع الحيوان من التصنيف المعتمد.")
            }
        case .bioVault:
            if viewModel.liveInventoryMode == .quantity {
                if viewModel.quantity < 1 {
                    return tr("LivePetIntake_ValidationQuantity", "أدخل كمية لا تقل عن حيوان واحد.")
                }
                if viewModel.liveSupplier.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 100 {
                    return tr("LivePetIntake_ValidationSupplierLength", "يجب ألا يتجاوز اسم المورد 100 حرف.")
                }
                if viewModel.liveIntakeNotes.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 {
                    return tr("LivePetIntake_ValidationNotesLength", "يجب ألا تتجاوز ملاحظات الاستلام 500 حرف.")
                }
                if viewModel.canViewStockCosts && !validMoney(viewModel.liveGroupCostText, allowsZero: true) {
                    return tr("LivePetIntake_ValidationCost", "أدخل تكلفة صحيحة بحد أقصى منزلتين عشريتين.")
                }
            } else if !viewModel.isEditingLivePet {
                if viewModel.livePetUnits.isEmpty {
                    return tr("LivePetIntake_ValidationUnit", "أضف حيواناً واحداً على الأقل.")
                }
                if viewModel.livePetUnits.contains(where: {
                    $0.supplier.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 100
                }) {
                    return tr("LivePetIntake_ValidationSupplierLength", "يجب ألا يتجاوز اسم المورد 100 حرف.")
                }
                if viewModel.livePetUnits.contains(where: {
                    $0.notes.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500
                }) {
                    return tr("LivePetIntake_ValidationNotesLength", "يجب ألا تتجاوز ملاحظات الاستلام 500 حرف.")
                }
                let normalized = viewModel.livePetUnits.map {
                    $0.ringTag.precomposedStringWithCompatibilityMapping
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .lowercased(with: Locale(identifier: "en_US_POSIX"))
                }
                if normalized.contains(where: { $0.isEmpty || $0.utf16.count > 80 }) {
                    return tr("LivePetIntake_ValidationRing", "أكمل رقم الحلقة أو الشريحة لكل حيوان.")
                }
                if Set(normalized).count != normalized.count {
                    return tr("LivePetIntake_ValidationDuplicate", "أرقام الحلقات أو الشرائح مكررة داخل الإدخال.")
                }
                if !viewModel.livePetUnits.allSatisfy({ validMoney($0.sellingPriceText, allowsZero: false) }) {
                    return tr("LivePetIntake_ValidationUnitPrice", "أدخل سعر بيع صحيحاً لكل حيوان.")
                }
                if viewModel.canViewStockCosts,
                   !viewModel.livePetUnits.allSatisfy({ validMoney($0.purchaseCostText, allowsZero: true) }) {
                    return tr("LivePetIntake_ValidationCost", "أدخل تكلفة صحيحة بحد أقصى منزلتين عشريتين.")
                }
            }
        case .pricing:
            if !validMoney(viewModel.priceText, allowsZero: false) {
                return tr("LivePetIntake_ValidationPrice", "حدد سعراً أساسياً صحيحاً أكبر من صفر.")
            }
            if viewModel.liveInventoryMode == .quantity && !viewModel.isValidDiscountPercentInput() {
                return tr("LivePetIntake_ValidationDiscountPercent", "أدخل نسبة خصم بين 0 و100 وبحد أقصى منزلتين عشريتين.")
            }
            if viewModel.liveInventoryMode == .quantity && !viewModel.isValidDiscountAmountInput() {
                return tr("LivePetIntake_ValidationDiscountAmount", "أدخل مبلغ خصم صالحاً وبحد أقصى منزلتين عشريتين.")
            }
        case .governance:
            if viewModel.selectedStoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return tr("LivePetIntake_ValidationBranch", "اختر الفرع المالك لهذا المخزون.")
            }
        }
        return nil
    }

    private func validMoney(_ text: String, allowsZero: Bool) -> Bool {
        let clean = text.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(clean), value <= 999_999_999.99 else { return false }
        return allowsZero ? value >= 0 : value > 0
    }

    private func move(to stage: PPEditorStage, preservingMessage: Bool = false) {
        focusedField = nil
        if !preservingMessage {
            stageMessage = nil
        }
        UISelectionFeedbackGenerator().selectionChanged()
        if accessibilityReduceMotion {
            viewModel.activeStage = stage
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                viewModel.activeStage = stage
            }
        }
    }

    private func setExpandedUnit(_ id: String?) {
        if accessibilityReduceMotion {
            expandedUnitID = id
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                expandedUnitID = id
            }
        }
    }

    private func stageTitle(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("LivePetIntake_StageIdentity", "الهوية")
        case .bioVault: return tr("LivePetIntake_StageIntake", "الإدخال")
        case .pricing: return tr("LivePetIntake_StagePricing", "التسعير")
        case .governance: return tr("LivePetIntake_StageRelease", "الإتاحة")
        }
    }

    private func stageQuestion(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("LivePetIntake_QuestionIdentity", "من هو الحيوان، وكيف سيظهر؟")
        case .bioVault: return tr("LivePetIntake_QuestionIntake", "كيف ستُحفظ هويته في المخزون؟")
        case .pricing: return tr("LivePetIntake_QuestionPricing", "ما السعر المرجعي للبيع؟")
        case .governance: return tr("LivePetIntake_QuestionRelease", "أين يُنسب السجل، وهل يظهر الآن؟")
        }
    }

    private func progressColor(for stage: PPEditorStage) -> Color {
        if stage == viewModel.activeStage { return AdminSurface.primary }
        return validationMessage(for: stage) == nil
            ? Color(uiColor: .ppSuccess)
            : AdminSurface.secondaryText
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: AdminSpacing.xs) {
            Text(text)
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.secondaryText)
            if required {
                Text(tr("LivePetIntake_Required", "مطلوب"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, AdminSpacing.xs)
                    .padding(.vertical, 2)
                    .background(AdminSurface.primary.opacity(0.09), in: Capsule())
            }
        }
    }

    private func fieldFocusBorder(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
            .strokeBorder(focused ? AdminSurface.primary : AdminSurface.hairline.opacity(0.7), lineWidth: focused ? 1.5 : 0.75)
    }

    private func operationalCallout(title: String, message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(message)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AdminSpacing.md)
        .background(color.opacity(0.085), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func tr(_ key: String, _ fallback: String) -> String {
        Language.get(key, alter: fallback)
    }
}

private struct PPLivePetDecisionSurface<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sectionSpacing) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 46, height: 46)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(eyebrow.uppercased())
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                    Text(title)
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            content
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.72), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
    }
}

private struct PPLivePetJourneyMapSheet: View {
    let activeStage: PPEditorStage
    let completedStages: Set<PPEditorStage>
    let onSelect: (PPEditorStage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                            Text(Language.get("LivePetIntake_JourneyTitle", alter: "مسار إدخال الحيوان"))
                                .font(AdminType.title2)
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("LivePetIntake_JourneySubtitle", alter: "انتقل إلى أي خطوة. الحفظ النهائي يتحقق من المسار بالكامل."))
                                .font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)

                        VStack(spacing: AdminSpacing.sm) {
                            ForEach(PPEditorStage.allCases) { stage in
                                stageRow(stage)
                            }
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func stageRow(_ stage: PPEditorStage) -> some View {
        let selected = stage == activeStage
        let complete = completedStages.contains(stage)
        return Button {
            onSelect(stage)
        } label: {
            HStack(spacing: AdminSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .fill(selected ? AdminSurface.primary : AdminSurface.control)
                        .frame(width: 48, height: 48)
                    Text(verbatim: String(format: "%02d", stage.rawValue + 1).normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(selected ? .white : AdminSurface.primary)
                }
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(title(stage))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(question(stage))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: AdminSpacing.xs)
                Image(systemName: complete ? "checkmark.circle.fill" : (selected ? "record.circle" : "circle.dashed"))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(complete ? Color(uiColor: .ppSuccess) : (selected ? AdminSurface.primary : AdminSurface.secondaryText))
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: selected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(complete
            ? Language.get("Complete", alter: "مكتمل")
            : Language.get("LivePetIntake_NeedsWork", alter: "يحتاج استكمالاً"))
    }

    private func title(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return Language.get("LivePetIntake_StageIdentity", alter: "الهوية")
        case .bioVault: return Language.get("LivePetIntake_StageIntake", alter: "الإدخال")
        case .pricing: return Language.get("LivePetIntake_StagePricing", alter: "التسعير")
        case .governance: return Language.get("LivePetIntake_StageRelease", alter: "الإتاحة")
        }
    }

    private func question(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return Language.get("LivePetIntake_QuestionIdentity", alter: "من هو الحيوان، وكيف سيظهر؟")
        case .bioVault: return Language.get("LivePetIntake_QuestionIntake", alter: "كيف ستُحفظ هويته في المخزون؟")
        case .pricing: return Language.get("LivePetIntake_QuestionPricing", alter: "ما السعر المرجعي للبيع؟")
        case .governance: return Language.get("LivePetIntake_QuestionRelease", alter: "أين يُنسب السجل، وهل يظهر الآن؟")
        }
    }
}

private struct PPLivePetChoice: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    var sectionHeader: String? = nil
}

private struct PPCatalogMultiChoiceSheet: View {
    let title: String
    let subtitle: String
    let searchPrompt: String
    let allOptionTitle: String
    let allOptionSubtitle: String?
    let allOptionSymbol: String
    let choices: [PPLivePetChoice]
    @Binding var isAllSelected: Bool
    @Binding var selectedIDs: Set<String>
    var onRefresh: (() -> Void)? = nil
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredChoices: [PPLivePetChoice] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return choices }
        return choices.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(title)
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(subtitle)
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)

                    // Search Field
                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AdminSurface.secondaryText)
                        TextField(searchPrompt, text: $query)
                            .font(AdminType.body)
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                            }
                            .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                        }
                    }
                    .padding(.leading, AdminSpacing.md)
                    .frame(minHeight: AdminTouchTarget.expanded)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)

                    ScrollView {
                        LazyVStack(spacing: AdminSpacing.sm) {
                            // "ALL" Option Card
                            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                allOptionCard
                            }

                            if filteredChoices.isEmpty {
                                VStack(spacing: AdminSpacing.md) {
                                    Image(systemName: "magnifyingglass.circle")
                                        .font(.system(size: 42, weight: .light))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                    Text(Language.get("CatalogIntake_NoCategories", alter: "لا توجد نتائج مطابقة"))
                                        .font(AdminType.headline)
                                        .foregroundStyle(AdminSurface.primaryText)
                                }
                                .padding(.top, AdminSpacing.xxl)
                            } else {
                                ForEach(Array(filteredChoices.enumerated()), id: \.element.id) { index, choice in
                                    if let header = choice.sectionHeader, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        let previousHeader = index > 0 ? filteredChoices[index - 1].sectionHeader : nil
                                        if index == 0 || header != previousHeader {
                                            sectionSeparator(title: header, isFirst: index == 0)
                                        }
                                    }
                                    choiceRow(choice)
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.sm)
                        .padding(.bottom, 90)
                    }
                    .refreshable {
                        onRefresh?()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
                if let onRefresh {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                confirmActionBar
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var allOptionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                if isAllSelected {
                    isAllSelected = false
                } else {
                    isAllSelected = true
                    selectedIDs.removeAll()
                }
            }
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: allOptionSymbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isAllSelected ? .white : AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(isAllSelected ? AdminSurface.primary : AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(allOptionTitle)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    if let sub = allOptionSubtitle {
                        Text(sub)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isAllSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 12)
            .background(
                isAllSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(isAllSelected ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: isAllSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private func choiceRow(_ choice: PPLivePetChoice) -> some View {
        let isSelected = !isAllSelected && selectedIDs.contains(choice.id)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if isAllSelected {
                    isAllSelected = false
                    selectedIDs = [choice.id]
                } else if selectedIDs.contains(choice.id) {
                    selectedIDs.remove(choice.id)
                } else {
                    selectedIDs.insert(choice.id)
                }
            }
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? AdminSurface.primary : AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(choice.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    if let subtitle = choice.subtitle {
                        Text(subtitle)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.35))
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 10)
            .background(
                isSelected ? AdminSurface.primary.opacity(0.06) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(isSelected ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline, lineWidth: isSelected ? 1.2 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private var confirmActionBar: some View {
        VStack(spacing: 0) {
            Divider().background(AdminSurface.hairline)

            HStack(spacing: 12) {
                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                    if isAllSelected {
                        Text(allOptionTitle)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    } else if !selectedIDs.isEmpty {
                        Text(verbatim: String(format: Language.get("CatalogIntake_SelectedCountFormat", alter: "تم تحديد %@"), selectedIDs.count.englishDigits).normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    } else {
                        Text(Language.get("CatalogIntake_NoSelection", alter: "لم يتم التحديد"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConfirm()
                    dismiss()
                } label: {
                    Text(Language.get("Confirm_Selection", alter: "تأكيد الاختيار"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AdminSurface.primary, in: Capsule())
                }
                .disabled(!isAllSelected && selectedIDs.isEmpty)
                .opacity((!isAllSelected && selectedIDs.isEmpty) ? 0.5 : 1.0)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 12)
            .background(AdminSurface.surface.ignoresSafeArea(edges: .bottom))
        }
    }

    private func sectionSeparator(title: String, isFirst: Bool) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)

            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                Text(title)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.xs)
            .background(AdminSurface.primary.opacity(0.08), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
            )

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
        }
        .padding(.top, isFirst ? AdminSpacing.xs : AdminSpacing.md)
        .padding(.bottom, AdminSpacing.xxs)
    }
}

private struct PPLivePetChoiceSheet: View {
    let title: String
    let subtitle: String
    let searchPrompt: String
    let emptyTitle: String
    let selectedID: String?
    let choices: [PPLivePetChoice]
    var onRefresh: (() -> Void)? = nil
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredChoices: [PPLivePetChoice] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return choices }
        return choices.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                VStack(spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(title)
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(subtitle)
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AdminSurface.secondaryText)
                        TextField(searchPrompt, text: $query)
                            .font(AdminType.body)
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                            }
                            .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                        }
                    }
                    .padding(.leading, AdminSpacing.md)
                    .frame(minHeight: AdminTouchTarget.expanded)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    ScrollView {
                        LazyVStack(spacing: AdminSpacing.sm) {
                            if filteredChoices.isEmpty {
                                VStack(spacing: AdminSpacing.md) {
                                    Image(systemName: "magnifyingglass.circle")
                                        .font(.system(size: 42, weight: .light))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                    Text(emptyTitle)
                                        .font(AdminType.headline)
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(Language.get("CatalogIntake_TryAnotherSearch", alter: "جرّب كلمة أخرى أو امسح البحث."))
                                        .font(AdminType.footnote)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                                .padding(.top, AdminSpacing.xxl)
                            } else {
                                ForEach(Array(filteredChoices.enumerated()), id: \.element.id) { index, choice in
                                    if let header = choice.sectionHeader, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        let previousHeader = index > 0 ? filteredChoices[index - 1].sectionHeader : nil
                                        if index == 0 || header != previousHeader {
                                            sectionSeparator(title: header, isFirst: index == 0)
                                        }
                                    }
                                    choiceRow(choice)
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.lg)
                    }
                    .refreshable {
                        onRefresh?()
                    }
                }
                .padding(.top, AdminSpacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
                if let onRefresh {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func choiceRow(_ choice: PPLivePetChoice) -> some View {
        let selected = choice.id == selectedID
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect(choice.id)
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(selected ? AdminSurface.primary : AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(choice.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                    if let subtitle = choice.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: AdminSpacing.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.forward")
                    .font(.system(size: selected ? 20 : 12, weight: .semibold))
                    .foregroundStyle(selected ? AdminSurface.primary : AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: selected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionSeparator(title: String, isFirst: Bool) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)

            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                Text(title)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.xs)
            .background(AdminSurface.primary.opacity(0.08), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
            )

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
        }
        .padding(.top, isFirst ? AdminSpacing.xs : AdminSpacing.md)
        .padding(.bottom, AdminSpacing.xxs)
    }
}

struct PPLivePetPreviewMedia: Identifiable {
    enum Source {
        case local(UIImage)
        case remote(URL)
    }

    let id = UUID()
    let source: Source
}

struct PPLivePetMediaPreview: View {
    let media: PPLivePetPreviewMedia
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var settledScale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    private var displayScale: CGFloat {
        min(4, max(1, settledScale * gestureScale))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            mediaContent
                .scaledToFit()
                .scaleEffect(displayScale)
                .gesture(
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in state = value }
                        .onEnded { value in
                            settledScale = min(4, max(1, settledScale * value))
                        }
                )
                .onTapGesture(count: 2) {
                    let target: CGFloat = settledScale > 1 ? 1 : 2.5
                    if accessibilityReduceMotion {
                        settledScale = target
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) { settledScale = target }
                    }
                }
                .accessibilityLabel(Language.get("CatalogIntake_PhotoPreview", alter: "معاينة صورة الصنف"))
                .accessibilityValue(String(
                    format: Language.get("CatalogIntake_ZoomValueFormat", alter: "التكبير %ld بالمئة"),
                    Int((settledScale * 100).rounded())
                ))
                .accessibilityHint(Language.get(
                    "CatalogIntake_PhotoZoomHint",
                    alter: "استخدم إجراءات التكبير أو التصغير لضبط المعاينة"
                ))
                .accessibilityAction(named: Text(Language.get("CatalogIntake_ZoomIn", alter: "تكبير"))) {
                    adjustZoom(by: 0.5)
                }
                .accessibilityAction(named: Text(Language.get("CatalogIntake_ZoomOut", alter: "تصغير"))) {
                    adjustZoom(by: -0.5)
                }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        adjustZoom(by: 0.5)
                    case .decrement:
                        adjustZoom(by: -0.5)
                    @unknown default:
                        break
                    }
                }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.62), in: Circle())
            }
            .padding(AdminSpacing.base)
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
        }
        .statusBar(hidden: true)
    }

    private func adjustZoom(by delta: CGFloat) {
        let target = min(4, max(1, settledScale + delta))
        if accessibilityReduceMotion {
            settledScale = target
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                settledScale = target
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch media.source {
        case .local(let image):
            Image(uiImage: image).resizable()
        case .remote(let url):
            AdminRemoteImage(url: url, contentMode: .fit) {
                VStack(spacing: AdminSpacing.md) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 42))
                    Text(Language.get("CatalogIntake_PhotoLoadFailed", alter: "تعذر تحميل الصورة"))
                        .font(AdminType.headline)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct PPLivePetPhotoPicker: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPicked: ([UIImage], Int) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = maxSelection
        configuration.filter = .images
        if #available(iOS 15.0, *) {
            configuration.selection = .ordered
        }
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private final class LoadAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var orderedImages: [UIImage?]
        private var failedCount = 0

        init(count: Int) {
            orderedImages = Array(repeating: nil, count: count)
        }

        func record(image: UIImage, at index: Int) {
            lock.lock()
            orderedImages[index] = image
            lock.unlock()
        }

        func recordFailure() {
            lock.lock()
            failedCount += 1
            lock.unlock()
        }

        func snapshot() -> ([UIImage], Int) {
            lock.lock()
            let images = orderedImages.compactMap { $0 }
            let failures = failedCount
            lock.unlock()
            return (images, failures)
        }
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PPLivePetPhotoPicker

        init(parent: PPLivePetPhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else { return }

            let accumulator = LoadAccumulator(count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                    accumulator.recordFailure()
                    continue
                }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        accumulator.record(image: image, at: index)
                    } else {
                        accumulator.recordFailure()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let (images, failedCount) = accumulator.snapshot()
                self.parent.onPicked(images, failedCount)
            }
        }
    }
}

struct PPLivePetCameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PPLivePetCameraPicker

        init(parent: PPLivePetCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.dismiss()
                return
            }
            parent.onPicked(image)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PPLivePetPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func scrollContentBackgroundIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Hosting Controller Bridge

@objc @MainActor public final class PPAccessoryEditorHostingBridge: NSObject {
    @objc public static func makeViewController(
        accessory: PetAccessory?,
        showTypeRow: Bool,
        defaultKind: AccessKindType,
        onDismiss: @escaping @Sendable () -> Void
    ) -> UIViewController {
        let viewModel = PPAccessoryEditorViewModel(
            accessory: accessory,
            showTypeRow: showTypeRow,
            defaultKind: defaultKind,
            onDismiss: onDismiss
        )
        let host = UIHostingController(rootView: PPAccessoryEditorExperienceRouter(viewModel: viewModel))
        host.view.backgroundColor = .clear
        return host
    }
}

// MARK: - Category-Defining Tactile Product Condition Matrix

private struct PPAccessoryConditionSelector: View {
    @Binding var condition: AccessConditions
    let isFood: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            // Header Row
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("CatalogIntake_ConditionLabel", alter: "حالة المنتج"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text("*")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(uiColor: .ppError))
                    .accessibilityHidden(true)

                Spacer(minLength: 4)

                // Live status capsule
                if !isFood {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(condition == .new ? Color(red: 0.06, green: 0.72, blue: 0.51) : Color(red: 0.96, green: 0.62, blue: 0.15))
                            .frame(width: 6, height: 6)

                        Text(condition == .new ? Language.get("Condition_New_Badge", alter: "جديد ومغلف") : Language.get("Condition_Used_Badge", alter: "مستعمل ومعتمد"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(condition == .new ? Color(red: 0.06, green: 0.72, blue: 0.51) : Color(red: 0.96, green: 0.62, blue: 0.15))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(
                                condition == .new
                                    ? Color(red: 0.06, green: 0.72, blue: 0.51).opacity(colorScheme == .dark ? 0.18 : 0.08)
                                    : Color(red: 0.96, green: 0.62, blue: 0.15).opacity(colorScheme == .dark ? 0.18 : 0.08)
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                condition == .new
                                    ? Color(red: 0.06, green: 0.72, blue: 0.51).opacity(0.28)
                                    : Color(red: 0.96, green: 0.62, blue: 0.15).opacity(0.28),
                                lineWidth: 0.75
                            )
                    )
                }
            }
            .accessibilityElement(children: .combine)

            if isFood {
                // Certified Food Safety & Seal Notice
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.72, blue: 0.51).opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .frame(width: 38, height: 38)

                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color(red: 0.06, green: 0.72, blue: 0.51))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("CatalogIntake_FoodCondition_Title", alter: "أغذية ومكملات جديدة ومغلفة حصراً"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("CatalogIntake_FoodCondition_Sub", alter: "تخضع كافة أطعمة ومكملات الحيوانات الأليفة لمعايير السلامة الغذائية وتُحفظ دائماً بحالة جديدة ومغلفة لضمان أعلى معايير السلامة والصحة البيطرية."))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.06, green: 0.72, blue: 0.51).opacity(colorScheme == .dark ? 0.08 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.06, green: 0.72, blue: 0.51).opacity(0.25), lineWidth: 0.8)
                )
            } else {
                // Bilateral Tactile Quality Cards
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            conditionTile(
                                target: .new,
                                icon: "checkmark.seal.fill",
                                title: Language.get("Condition_New", alter: "جديد تماماً"),
                                subtitle: Language.get("Condition_New_Sub", alter: "مغلف المصنع • أصلي 100%"),
                                accent: Color(red: 0.06, green: 0.72, blue: 0.51)
                            )
                            conditionTile(
                                target: .used,
                                icon: "sparkle.magnifyingglass",
                                title: Language.get("Condition_Used", alter: "مستعمل بحالة جيدة"),
                                subtitle: Language.get("Condition_Used_Sub", alter: "مفحوص ومعتمد • جاهز للاستخدام"),
                                accent: Color(red: 0.96, green: 0.62, blue: 0.15)
                            )
                        }
                    } else {
                        HStack(spacing: 10) {
                            conditionTile(
                                target: .new,
                                icon: "checkmark.seal.fill",
                                title: Language.get("Condition_New", alter: "جديد تماماً"),
                                subtitle: Language.get("Condition_New_Sub", alter: "مغلف المصنع • أصلي 100%"),
                                accent: Color(red: 0.06, green: 0.72, blue: 0.51)
                            )
                            conditionTile(
                                target: .used,
                                icon: "sparkle.magnifyingglass",
                                title: Language.get("Condition_Used", alter: "مستعمل بحالة جيدة"),
                                subtitle: Language.get("Condition_Used_Sub", alter: "مفحوص ومعتمد • جاهز للاستخدام"),
                                accent: Color(red: 0.96, green: 0.62, blue: 0.15)
                            )
                        }
                    }
                }
            }
        }
    }

    private func conditionTile(
        target: AccessConditions,
        icon: String,
        title: String,
        subtitle: String,
        accent: Color
    ) -> some View {
        let isSelected = condition == target
        return Button {
            guard condition != target else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                condition = target
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            isSelected
                                ? accent.opacity(colorScheme == .dark ? 0.28 : 0.14)
                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? accent : AdminSurface.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                            .lineLimit(1)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(accent)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(isSelected ? AdminCommandInk.secondary : AdminSurface.secondaryText.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                }

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                                ? (colorScheme == .dark ? Color(white: 0.13) : Color.white)
                                : AdminSurface.control
                        )

                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
                                        accent.opacity(colorScheme == .dark ? 0.04 : 0.01)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? accent.opacity(colorScheme == .dark ? 0.65 : 0.45)
                            : AdminSurface.hairline.opacity(0.70),
                        lineWidth: isSelected ? 1.4 : 0.75
                    )
            )
            .shadow(
                color: isSelected ? accent.opacity(colorScheme == .dark ? 0.22 : 0.10) : Color.black.opacity(0.02),
                radius: isSelected ? 6 : 2,
                x: 0,
                y: isSelected ? 2 : 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Category-Defining Tactile Item Size Selector Chamber

private struct PPAccessorySizeSelector: View {
    @Binding var size: String

    @FocusState private var isCustomFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Standard high-demand apparel & accessory sizes
    private let standardPresetSizes: [String] = [
        "XXS", "XS", "S", "M", "L", "XL", "XXL", "3XL"
    ]

    private var isSelectedUniversal: Bool {
        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "free size" || trimmed == "موحد" || trimmed == "موحد (free size)"
    }

    private var activeSelectedBadgeText: String? {
        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon + Title + Live Badge + Clear
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 20)

                Text(Language.get("CatalogIntake_SizeLabel", alter: "المقاس المطلوب"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("CatalogIntake_Optional", alter: "(اختياري)"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer(minLength: 4)

                // Live Active Size Tag
                if let activeBadge = activeSelectedBadgeText {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(verbatim: activeBadge)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                size = ""
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.30), lineWidth: 0.75))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Presets Runway: Standard Apparel Sizing Grid / Horizontal Scroll
            VStack(alignment: .leading, spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Free Size Pill
                        let isFreeSelected = isSelectedUniversal
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                size = isFreeSelected ? "" : "Free Size"
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(Language.get("Size_FreeSize", alter: "موحد (Free Size)"))
                                    .font(PPBrandFont.bold(size: 11.5))
                            }
                            .foregroundStyle(
                                isFreeSelected
                                    ? (colorScheme == .dark ? Color.white : AdminSurface.primary)
                                    : AdminSurface.primaryText.opacity(0.85)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        isFreeSelected
                                            ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.35 : 0.15)
                                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isFreeSelected ? AdminSurface.primary.opacity(0.60) : Color.clear,
                                        lineWidth: 0.9
                                    )
                            )
                        }
                        .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))

                        // Standard Pills (XXS -> 3XL)
                        ForEach(standardPresetSizes, id: \.self) { preset in
                            let isSelected = size.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(preset) == .orderedSame
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                    size = isSelected ? "" : preset
                                }
                            } label: {
                                Text(verbatim: preset)
                                    .font(PPBrandFont.bold(size: 12))
                                    .foregroundStyle(
                                        isSelected
                                            ? (colorScheme == .dark ? Color.white : AdminSurface.primary)
                                            : AdminSurface.primaryText.opacity(0.85)
                                    )
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(
                                                isSelected
                                                    ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.35 : 0.15)
                                                    : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                isSelected ? AdminSurface.primary.opacity(0.60) : Color.clear,
                                                lineWidth: 0.9
                                            )
                                    )
                            }
                            .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Custom Size Input Chamber
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.ruler")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCustomFieldFocused ? AdminSurface.primary : AdminSurface.secondaryText)
                        .padding(.leading, 12)

                    TextField(
                        Language.get("CatalogIntake_CustomSizePlaceholder", alter: "أو اكتب مقاساً مخصصاً (مثال: 45 سم، 14 إنش...)"),
                        text: $size
                    )
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .focused($isCustomFieldFocused)

                    if !size.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            size = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.70))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                    }
                }
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isCustomFieldFocused ? AdminSurface.primary : AdminSurface.hairline.opacity(0.85),
                            lineWidth: isCustomFieldFocused ? 1.4 : 0.75
                        )
                )
            }
        }
    }
}

// MARK: - Category-Defining Unified Physical Measure Chamber

private struct PPAccessoryUnifiedMeasureChamber: View {
    @Binding var weightText: String
    @Binding var weightUnit: String
    var onFocusChanged: ((Bool) -> Void)? = nil

    @FocusState private var isInternalFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let availableUnits: [String] = ["kg", "g", "L", "ml"]

    private var isVolumeDimension: Bool {
        weightUnit.lowercased() == "l" || weightUnit.lowercased() == "ml"
    }

    private var dimensionIcon: String {
        isVolumeDimension ? "drop.fill" : "scalemass.fill"
    }

    private var contextualPresets: [String] {
        switch weightUnit.lowercased() {
        case "kg": return ["0.5", "1.0", "2.0", "3.0", "5.0", "10", "15"]
        case "g": return ["100", "200", "250", "400", "500", "800"]
        case "l": return ["0.5", "1.0", "1.5", "2.0", "5.0", "10"]
        case "ml": return ["50", "100", "150", "250", "500", "750"]
        default: return ["1.0", "2.0", "5.0"]
        }
    }

    private var liveMetricDisplay: String? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let val = Double(trimmed), val > 0 else { return nil }

        let formattedVal = trimmed
        let isArabic = Language.isRTL()
        switch weightUnit.lowercased() {
        case "kg":
            let unitName = isArabic ? "كجم" : "kg"
            let subUnit = isArabic ? "جم" : "g"
            if val < 1.0 {
                let grams = Int(val * 1000)
                return "\(formattedVal) \(unitName) (\(grams) \(subUnit))".normalizedEnglishDigits
            }
            return "\(formattedVal) \(unitName)".normalizedEnglishDigits
        case "g":
            let unitName = isArabic ? "جم" : "g"
            let superUnit = isArabic ? "كجم" : "kg"
            if val >= 1000 {
                let kg = val / 1000.0
                let kgStr = String(format: "%.2f", kg).replacingOccurrences(of: ".00", with: "")
                return "\(formattedVal) \(unitName) (\(kgStr) \(superUnit))".normalizedEnglishDigits
            }
            return "\(formattedVal) \(unitName)".normalizedEnglishDigits
        case "l":
            let unitName = isArabic ? "لتر" : "L"
            let subUnit = isArabic ? "مل" : "ml"
            if val < 1.0 {
                let ml = Int(val * 1000)
                return "\(formattedVal) \(unitName) (\(ml) \(subUnit))".normalizedEnglishDigits
            }
            return "\(formattedVal) \(unitName)".normalizedEnglishDigits
        case "ml":
            let unitName = isArabic ? "مل" : "ml"
            let superUnit = isArabic ? "لتر" : "L"
            if val >= 1000 {
                let liters = val / 1000.0
                let lStr = String(format: "%.2f", liters).replacingOccurrences(of: ".00", with: "")
                return "\(formattedVal) \(unitName) (\(lStr) \(superUnit))".normalizedEnglishDigits
            }
            return "\(formattedVal) \(unitName)".normalizedEnglishDigits
        default:
            return "\(formattedVal) \(weightUnit)".normalizedEnglishDigits
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Header Row: Adaptive Icon + Title + Live Physical Preview
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: dimensionIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isVolumeDimension ? Color(red: 0.14, green: 0.54, blue: 0.98) : AdminSurface.primary)
                    .frame(width: 20)

                Text(Language.get("CatalogIntake_WeightLabel", alter: "الوزن أو السعة"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("CatalogIntake_Optional", alter: "(اختياري)"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer(minLength: 4)

                // Live Physical Metric Tag
                if let livePreview = liveMetricDisplay {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(livePreview)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.30), lineWidth: 0.75))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Unified Sculpted Chamber
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        numericInputField
                        unitSelectorDock
                    }
                    .padding(10)
                } else {
                    HStack(spacing: 0) {
                        numericInputField
                        
                        // Vertical Separation Hairline
                        Rectangle()
                            .fill(AdminSurface.hairline.opacity(0.85))
                            .frame(width: 1, height: 32)
                            .padding(.horizontal, 4)

                        unitSelectorDock
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isInternalFocused ? AdminSurface.primary : AdminSurface.hairline.opacity(0.85),
                        lineWidth: isInternalFocused ? 1.5 : 0.75
                    )
            )
            .shadow(
                color: isInternalFocused ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.25 : 0.12) : Color.clear,
                radius: 6,
                x: 0,
                y: 1
            )

            // Contextual Quick-Magnitude Presets Runway
            HStack(spacing: 6) {
                Text(Language.get("CatalogIntake_QuickPresets", alter: "مقادير سريعة:"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(contextualPresets, id: \.self) { preset in
                            let isSelected = weightText == preset
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                    weightText = preset
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(verbatim: preset.normalizedEnglishDigits)
                                        .font(PPBrandFont.bold(size: 12))
                                    Text(weightUnit)
                                        .font(PPBrandFont.medium(size: 10))
                                }
                                .foregroundStyle(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white : AdminSurface.primary)
                                        : AdminSurface.primaryText.opacity(0.85)
                                )
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                                .background(
                                    Capsule()
                                        .fill(
                                            isSelected
                                                ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.35 : 0.15)
                                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? AdminSurface.primary.opacity(0.60) : Color.clear,
                                            lineWidth: 0.8
                                        )
                                    )
                            }
                            .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var numericInputField: some View {
        HStack(spacing: 8) {
            TextField("0.0", text: $weightText)
                .font(PPBrandFont.bold(size: 24))
                .foregroundStyle(AdminSurface.primaryText)
                .englishNumericInput(text: $weightText, allowsDecimal: true)
                .focused($isInternalFocused)
                .onChange(of: isInternalFocused) { focused in
                    onFocusChanged?(focused)
                }

            if !weightText.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    weightText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.70))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Clear", alter: "مسح"))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private var unitSelectorDock: some View {
        HStack(spacing: 3) {
            ForEach(availableUnits, id: \.self) { unit in
                unitButton(unit: unit)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
    }

    private func unitButton(unit: String) -> some View {
        let isSelected = weightUnit.lowercased() == unit.lowercased()
        return Button {
            guard weightUnit.lowercased() != unit.lowercased() else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                weightUnit = unit
            }
        } label: {
            Text(unit)
                .font(PPBrandFont.medium(size: 13))
                .foregroundStyle(unitButtonForeground(isSelected: isSelected))
                .frame(minWidth: 32)
                .frame(height: 34)
                .background(unitButtonBackground(isSelected: isSelected))
                .overlay(unitButtonOverlay(isSelected: isSelected))
                .contentShape(Capsule())
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(localizedUnitAccessibility(unit))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func unitButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            let fillColor = (colorScheme == .dark)
                ? AdminSurface.primary.opacity(0.35)
                : Color.white
            let shadowColor = Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08)
            Capsule()
                .fill(fillColor)
                .shadow(color: shadowColor, radius: 3, x: 0, y: 1)
        }
    }

    private func unitButtonOverlay(isSelected: Bool) -> some View {
        let borderColor = isSelected ? AdminSurface.primary.opacity(0.50) : Color.clear
        return Capsule()
            .strokeBorder(borderColor, lineWidth: 0.75)
    }

    private func unitButtonForeground(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : AdminSurface.primary
        } else {
            return AdminSurface.secondaryText
        }
    }

    private func localizedUnitAccessibility(_ unit: String) -> String {
        switch unit.lowercased() {
        case "kg": return Language.get("Unit_Kilogram", alter: "كيلوجرام")
        case "g": return Language.get("Unit_Gram", alter: "جرام")
        case "l": return Language.get("Unit_Liter", alter: "لتر")
        case "ml": return Language.get("Unit_Milliliter", alter: "مليلتر")
        default: return unit
        }
    }
}

// MARK: - Category-Defining 2D Architectural Blueprint Patterns & Presets

private struct PPDimensionsGridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 16
        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

private struct PPCageMeshPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stepX: CGFloat = 12
        for x in stride(from: stepX, to: rect.width, by: stepX) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        let stepY: CGFloat = 12
        for y in stride(from: stepY, to: rect.height, by: stepY) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

private struct PPCageDimensionPreset: Identifiable {
    let id: String
    let width: Double
    let height: Double
    let unit: String
    let label: String
    let targetPet: String
}

//// MARK: - Category-Defining 2D & 3D Architectural Blueprint Canvas

private struct PPDimensionsBlueprintCanvas: View {
    let width: Double
    let height: Double
    let unit: String
    let isIPad: Bool

    @State private var is3DMode: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDimensions: Bool {
        width > 0 || height > 0
    }

    private var clampedAspectRatio: CGFloat {
        guard height > 0 else { return 1.4 }
        let rawRatio = CGFloat(width / height)
        return max(0.40, min(2.5, rawRatio))
    }

    private var displayUnitLocalized: String {
        switch unit.lowercased() {
        case "cm": return Language.get("PhysicalSpec_Unit_cm", alter: "سم")
        case "m": return Language.get("PhysicalSpec_Unit_m", alter: "م")
        case "in": return Language.get("PhysicalSpec_Unit_in", alter: "بوصة")
        case "mm": return Language.get("PhysicalSpec_Unit_mm", alter: "ملم")
        default: return unit
        }
    }

    private var areaTelemetryFormatted: String? {
        guard width > 0, height > 0 else { return nil }
        let area = width * height
        let isArabic = Language.isRTL()
        let areaStr = String(format: "%.1f", area).replacingOccurrences(of: ".0", with: "")

        switch unit.lowercased() {
        case "cm":
            let sqm = area / 10000.0
            let sqmStr = String(format: "%.2f", sqm).replacingOccurrences(of: ".00", with: "")
            let unitS = isArabic ? "سم²" : "cm²"
            let unitM = isArabic ? "م²" : "m²"
            return "\(areaStr) \(unitS) (\(sqmStr) \(unitM))".normalizedEnglishDigits
        case "m":
            let unitM = isArabic ? "م²" : "m²"
            return "\(areaStr) \(unitM)".normalizedEnglishDigits
        case "in":
            let sqft = area / 144.0
            let sqftStr = String(format: "%.2f", sqft).replacingOccurrences(of: ".00", with: "")
            let unitIn = isArabic ? "بوصة²" : "in²"
            let unitFt = isArabic ? "قدم²" : "sq ft"
            return "\(areaStr) \(unitIn) (\(sqftStr) \(unitFt))".normalizedEnglishDigits
        case "mm":
            let sqcm = area / 100.0
            let sqcmStr = String(format: "%.1f", sqcm).replacingOccurrences(of: ".0", with: "")
            let unitMm = isArabic ? "ملم²" : "mm²"
            let unitCm = isArabic ? "سم²" : "cm²"
            return "\(areaStr) \(unitMm) (\(sqcmStr) \(unitCm))".normalizedEnglishDigits
        default:
            return "\(areaStr) \(unit)²".normalizedEnglishDigits
        }
    }

    private var volumeTelemetryFormatted: String? {
        guard width > 0, height > 0 else { return nil }
        let d = min(width, height) > 0 ? min(width, height) : max(width, height) * 0.70
        let vol = width * height * d
        let isArabic = Language.isRTL()
        let volStr = String(format: "%.1f", vol).replacingOccurrences(of: ".0", with: "")

        switch unit.lowercased() {
        case "cm":
            let liters = vol / 1000.0
            let litersStr = String(format: "%.1f", liters).replacingOccurrences(of: ".0", with: "")
            let unitCm3 = isArabic ? "سم³" : "cm³"
            let unitL = isArabic ? "لتر" : "L"
            return "\(volStr) \(unitCm3) (\(litersStr) \(unitL))".normalizedEnglishDigits
        case "m":
            let unitM3 = isArabic ? "م³" : "m³"
            return "\(volStr) \(unitM3)".normalizedEnglishDigits
        case "in":
            let gallons = vol / 231.0
            let galStr = String(format: "%.1f", gallons).replacingOccurrences(of: ".0", with: "")
            let unitIn3 = isArabic ? "بوصة³" : "in³"
            let unitGal = isArabic ? "جالون" : "gal"
            return "\(volStr) \(unitIn3) (\(galStr) \(unitGal))".normalizedEnglishDigits
        case "mm":
            let ml = vol / 1000.0
            let mlStr = String(format: "%.1f", ml).replacingOccurrences(of: ".0", with: "")
            let unitMm3 = isArabic ? "ملم³" : "mm³"
            let unitMl = isArabic ? "مل" : "ml"
            return "\(volStr) \(unitMm3) (\(mlStr) \(unitMl))".normalizedEnglishDigits
        default:
            return "\(volStr) \(unit)³".normalizedEnglishDigits
        }
    }

    private var modeSwitcherButton: some View {
        HStack(spacing: 2) {
            Button {
                if is3DMode {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        is3DMode = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("2D")
                        .font(PPBrandFont.bold(size: 11))
                }
                .foregroundStyle(!is3DMode ? Color.white : AdminSurface.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    !is3DMode
                        ? Color(red: 0.20, green: 0.50, blue: 0.95)
                        : Color.clear,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("PhysicalSpec_Mode_2D", alter: "عرض ثنائي الأبعاد 2D"))

            Button {
                if !is3DMode {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        is3DMode = true
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 10, weight: .bold))
                    Text("3D")
                        .font(PPBrandFont.bold(size: 11))
                }
                .foregroundStyle(is3DMode ? Color.white : AdminSurface.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    is3DMode
                        ? Color(red: 0.20, green: 0.50, blue: 0.95)
                        : Color.clear,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("PhysicalSpec_Mode_3D", alter: "عرض ثلاثي الأبعاد 3D"))
        }
        .padding(2.5)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.92))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.35), lineWidth: 0.8)
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Blueprint Ambient Background Canvas
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.08, green: 0.12, blue: 0.20)
                            : Color(red: 0.94, green: 0.96, blue: 0.99)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                Color(red: 0.25, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.35 : 0.22),
                                lineWidth: 1.0
                            )
                    )

                // Architectural Gridlines
                PPDimensionsGridPattern()
                    .stroke(
                        Color(red: 0.30, green: 0.55, blue: 0.95).opacity(colorScheme == .dark ? 0.10 : 0.06),
                        lineWidth: 0.5
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Content: 3D Isometric View OR 2D Plan View
                if is3DMode {
                    if hasDimensions {
                        PPDimensionsIsometric3DView(
                            width: width,
                            height: height,
                            unit: unit,
                            displayUnit: displayUnitLocalized,
                            isIPad: isIPad
                        )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        // 3D Empty / Prompt State
                        VStack(spacing: 6) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(Color(red: 0.25, green: 0.50, blue: 0.95).opacity(0.85))

                            Text(Language.get("PhysicalSpec_Live3DBlueprint", alter: "مجسم هندسي ثلاثي الأبعاد 3D"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)

                            Text(Language.get("PhysicalSpec_3DPrompt", alter: "أدخل العرض والارتفاع لإنشاء المجسم ثلاثي الأبعاد والتحكم بزاوية الرؤية"))
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 16)
                    }
                } else {
                    if hasDimensions {
                        // Active Dimensioned Wireframe Box (2D)
                        GeometryReader { geo in
                            let maxW = geo.size.width - 70
                            let maxH = geo.size.height - 56
                            let boxAspect = clampedAspectRatio

                            let boxW: CGFloat = (boxAspect >= 1.0)
                                ? min(maxW, maxH * boxAspect)
                                : min(maxW, maxH * boxAspect)
                            let boxH: CGFloat = max(24, boxW / boxAspect)

                            ZStack {
                                // Proportional Wireframe Box
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.18 : 0.10))
                                    .frame(width: max(30, boxW), height: max(24, boxH))
                                    .overlay(
                                        PPCageMeshPattern()
                                            .stroke(
                                                Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.25),
                                                lineWidth: 0.75
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                Color(red: 0.20, green: 0.50, blue: 0.95),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .overlay(
                                        Button {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                                is3DMode = true
                                            }
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.12))
                                                    .frame(width: 30, height: 30)
                                                Image(systemName: "cube.transparent")
                                                    .font(.system(size: min(18, max(12, boxH * 0.35)), weight: .semibold))
                                                    .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(Language.get("PhysicalSpec_Mode_3D", alter: "تحويل إلى 3D"))
                                    )

                                // Dimension Annotation Line: Top (Width)
                                VStack(spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.left")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("\(String(format: "%g", width).normalizedEnglishDigits) \(displayUnitLocalized)")
                                            .font(PPBrandFont.bold(size: 11))
                                            .lineLimit(1)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.95))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(colorScheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.90))
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                }
                                .offset(y: -(max(24, boxH) / 2) - 16)

                                // Dimension Annotation Line: Trailing (Height)
                                HStack(spacing: 2) {
                                    VStack(spacing: 3) {
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("\(String(format: "%g", height).normalizedEnglishDigits)")
                                            .font(PPBrandFont.bold(size: 10.5))
                                            .lineLimit(1)
                                        Text(displayUnitLocalized)
                                            .font(PPBrandFont.medium(size: 9))
                                            .lineLimit(1)
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.95))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(colorScheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.90))
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                }
                                .offset(x: (max(30, boxW) / 2) + 26)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78), value: boxAspect)
                            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78), value: width)
                            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78), value: height)
                        }
                    } else {
                        // Empty / Prompt State (2D)
                        VStack(spacing: 6) {
                            Image(systemName: "ruler")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(Color(red: 0.25, green: 0.50, blue: 0.95).opacity(0.75))

                            Text(Language.get("PhysicalSpec_LiveBlueprint", alter: "مخطط هندسي حي للأقفاص والنواقل"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)

                            Text(Language.get("PhysicalSpec_BlueprintPrompt", alter: "أدخل العرض والارتفاع لرسم المخطط وتحديد التناسب تلقائياً"))
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 16)
                    }
                }

                // 2D / 3D Mode Switcher Pill (Top-Leading Corner)
                modeSwitcherButton
                    .padding(8)
            }
            .frame(height: isIPad ? (is3DMode ? 260 : 220) : (is3DMode ? 190 : 160))
            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78), value: is3DMode)

            // Telemetry Badge (3D Volume or 2D Footprint Area)
            if is3DMode, let volumeBadge = volumeTelemetryFormatted {
                HStack(spacing: 5) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))

                    Text(Language.get("PhysicalSpec_Volume", alter: "الحجم التقريبي:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(volumeBadge)
                        .font(PPBrandFont.bold(size: 12))
                        .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.20 : 0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.30), lineWidth: 0.75)
                )
                .transition(.scale.combined(with: .opacity))
            } else if let areaBadge = areaTelemetryFormatted {
                HStack(spacing: 5) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))

                    Text(Language.get("PhysicalSpec_Area", alter: "المساحة التقريبية:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(areaBadge)
                        .font(PPBrandFont.bold(size: 12))
                        .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.20 : 0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.30), lineWidth: 0.75)
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Category-Defining 3D Isometric Architectural Blueprint View

private struct PPDimensionsIsometric3DView: View {
    let width: Double
    let height: Double
    let unit: String
    let displayUnit: String
    let isIPad: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pitch: Double = 0
    @State private var yaw: Double = 0
    @State private var accumulatedPitch: Double = 0
    @State private var accumulatedYaw: Double = 0
    @State private var isDragging: Bool = false

    private var depth: Double {
        let minSide = min(width, height)
        let maxSide = max(width, height)
        if minSide > 0 {
            return minSide
        } else if maxSide > 0 {
            return maxSide * 0.70
        }
        return 30
    }

    private var hasBeenRotated: Bool {
        abs(accumulatedYaw) > 1 || abs(accumulatedPitch) > 1 || abs(yaw) > 1 || abs(pitch) > 1
    }

    var body: some View {
        GeometryReader { geo in
            let padW: CGFloat = isIPad ? 90 : 70
            let padH: CGFloat = isIPad ? 60 : 44
            let maxW = max(80, geo.size.width - padW)
            let maxH = max(60, geo.size.height - padH)

            let rawW = CGFloat(max(1, width))
            let rawH = CGFloat(max(1, height))
            let rawD = CGFloat(max(1, depth))

            let depthFactorX: CGFloat = 0.55
            let depthFactorY: CGFloat = 0.35

            let projW = rawW + (rawD * depthFactorX)
            let projH = rawH + (rawD * depthFactorY)

            let scale = min(maxW / projW, maxH / projH)
            let w = max(36, rawW * scale)
            let h = max(28, rawH * scale)
            let d = max(24, rawD * scale)
            let dx = d * depthFactorX
            let dy = d * depthFactorY

            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let x0 = cx - (w + dx) / 2
            let y0 = cy - (h - dy) / 2

            // 8 Canonical Isometric Vertices:
            let p0 = CGPoint(x: x0, y: y0)                   // Front Top-Left
            let p1 = CGPoint(x: x0 + w, y: y0)               // Front Top-Right
            let p2 = CGPoint(x: x0 + w, y: y0 + h)           // Front Bottom-Right
            let p3 = CGPoint(x: x0, y: y0 + h)               // Front Bottom-Left

            let p4 = CGPoint(x: x0 + dx, y: y0 - dy)         // Back Top-Left
            let p5 = CGPoint(x: x0 + w + dx, y: y0 - dy)     // Back Top-Right
            let p6 = CGPoint(x: x0 + w + dx, y: y0 + h - dy) // Back Bottom-Right
            let p7 = CGPoint(x: x0 + dx, y: y0 + h - dy)     // Back Bottom-Left

            ZStack {
                // 1. Back Interior Architectural Blueprint Hidden Edges (Dashed)
                Path { path in
                    path.move(to: p3)
                    path.addLine(to: p7)
                    path.addLine(to: p6)
                    path.move(to: p7)
                    path.addLine(to: p4)
                }
                .stroke(
                    Color(red: 0.35, green: 0.60, blue: 0.98).opacity(colorScheme == .dark ? 0.35 : 0.25),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                )

                // 2. Top Roof Face (Isometric Skewed)
                Path { path in
                    path.move(to: p0)
                    path.addLine(to: p4)
                    path.addLine(to: p5)
                    path.addLine(to: p1)
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.65, blue: 1.0).opacity(colorScheme == .dark ? 0.22 : 0.15),
                            Color(red: 0.25, green: 0.55, blue: 0.95).opacity(colorScheme == .dark ? 0.32 : 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Top Face Internal Wireframe Grid
                Path { path in
                    let steps = max(2, min(5, Int(w / 28)))
                    for i in 1..<steps {
                        let t = CGFloat(i) / CGFloat(steps)
                        let topStart = CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y)
                        let topEnd = CGPoint(x: p4.x + (p5.x - p4.x) * t, y: p4.y)
                        path.move(to: topStart)
                        path.addLine(to: topEnd)
                    }
                    let depthSteps = max(2, min(4, Int(d / 24)))
                    for j in 1..<depthSteps {
                        let u = CGFloat(j) / CGFloat(depthSteps)
                        let depthStart = CGPoint(x: p0.x + dx * u, y: p0.y - dy * u)
                        let depthEnd = CGPoint(x: p1.x + dx * u, y: p1.y - dy * u)
                        path.move(to: depthStart)
                        path.addLine(to: depthEnd)
                    }
                }
                .stroke(Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.28), lineWidth: 0.75)

                // Top Face Perimeter Stroke
                Path { path in
                    path.move(to: p0)
                    path.addLine(to: p4)
                    path.addLine(to: p5)
                    path.addLine(to: p1)
                    path.closeSubpath()
                }
                .stroke(Color(red: 0.30, green: 0.60, blue: 0.98), lineWidth: 1.5)

                // 3. Side Wall Face (Isometric Depth)
                Path { path in
                    path.move(to: p1)
                    path.addLine(to: p5)
                    path.addLine(to: p6)
                    path.addLine(to: p2)
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.40, blue: 0.85).opacity(colorScheme == .dark ? 0.28 : 0.18),
                            Color(red: 0.10, green: 0.32, blue: 0.75).opacity(colorScheme == .dark ? 0.38 : 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Side Face Internal Wireframe Grid
                Path { path in
                    let depthSteps = max(2, min(4, Int(d / 24)))
                    for j in 1..<depthSteps {
                        let u = CGFloat(j) / CGFloat(depthSteps)
                        let sideTop = CGPoint(x: p1.x + dx * u, y: p1.y - dy * u)
                        let sideBottom = CGPoint(x: p2.x + dx * u, y: p2.y - dy * u)
                        path.move(to: sideTop)
                        path.addLine(to: sideBottom)
                    }
                    let hSteps = max(2, min(5, Int(h / 24)))
                    for k in 1..<hSteps {
                        let v = CGFloat(k) / CGFloat(hSteps)
                        let sideLeft = CGPoint(x: p1.x, y: p1.y + h * v)
                        let sideRight = CGPoint(x: p5.x, y: p5.y + h * v)
                        path.move(to: sideLeft)
                        path.addLine(to: sideRight)
                    }
                }
                .stroke(Color(red: 0.25, green: 0.55, blue: 0.95).opacity(0.28), lineWidth: 0.75)

                // Side Face Perimeter Stroke
                Path { path in
                    path.move(to: p1)
                    path.addLine(to: p5)
                    path.addLine(to: p6)
                    path.addLine(to: p2)
                    path.closeSubpath()
                }
                .stroke(Color(red: 0.20, green: 0.50, blue: 0.95), lineWidth: 1.5)

                // 4. Front Face (Primary Facade)
                Path { path in
                    path.move(to: p0)
                    path.addLine(to: p1)
                    path.addLine(to: p2)
                    path.addLine(to: p3)
                    path.closeSubpath()
                }
                .fill(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.18 : 0.10))

                // Front Face Mesh Pattern
                PPCageMeshPattern()
                    .stroke(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.25), lineWidth: 0.75)
                    .clipShape(
                        Path { path in
                            path.move(to: p0)
                            path.addLine(to: p1)
                            path.addLine(to: p2)
                            path.addLine(to: p3)
                            path.closeSubpath()
                        }
                    )

                // Front Face Perimeter Stroke
                Path { path in
                    path.move(to: p0)
                    path.addLine(to: p1)
                    path.addLine(to: p2)
                    path.addLine(to: p3)
                    path.closeSubpath()
                }
                .stroke(Color(red: 0.20, green: 0.50, blue: 0.95), lineWidth: 1.5)

                // 5. Corner Glowing Vertices
                ForEach([p0, p1, p2, p3, p4, p5, p6], id: \.x) { pt in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .shadow(color: Color(red: 0.20, green: 0.50, blue: 0.95), radius: 3)
                        .position(pt)
                }

                // 6. 3D Spatial Dimension Callouts:
                // Width Callout (Front Bottom)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("\(String(format: "%g", width).normalizedEnglishDigits) \(displayUnit)")
                        .font(PPBrandFont.bold(size: 10.5))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.75) : Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                )
                .position(x: (p3.x + p2.x) / 2, y: p2.y + 14)

                // Height Callout (Front Left)
                VStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("\(String(format: "%g", height).normalizedEnglishDigits)")
                        .font(PPBrandFont.bold(size: 10))
                        .lineLimit(1)
                    Text(displayUnit)
                        .font(PPBrandFont.medium(size: 8.5))
                        .lineLimit(1)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.95))
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.75) : Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                )
                .position(x: max(14, p0.x - 22), y: (p0.y + p3.y) / 2)

                // Depth Callout (Top Receding Edge)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("\(String(format: "%g", depth).normalizedEnglishDigits) \(displayUnit)")
                        .font(PPBrandFont.bold(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.75) : Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                )
                .position(x: min(geo.size.width - 24, (p1.x + p5.x) / 2 + 18), y: max(14, (p1.y + p5.y) / 2 - 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotation3DEffect(
                .degrees(pitch),
                axis: (x: 1, y: 0, z: 0)
            )
            .rotation3DEffect(
                .degrees(yaw),
                axis: (x: 0, y: 1, z: 0)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { val in
                        isDragging = true
                        yaw = accumulatedYaw + Double(val.translation.width) * 0.35
                        pitch = max(-35, min(35, accumulatedPitch - Double(val.translation.height) * 0.35))
                    }
                    .onEnded { _ in
                        isDragging = false
                        accumulatedYaw = yaw
                        accumulatedPitch = pitch
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                if hasBeenRotated {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            pitch = 0
                            yaw = 0
                            accumulatedPitch = 0
                            accumulatedYaw = 0
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9, weight: .bold))
                            Text(Language.get("Reset", alter: "إعادة الضبط"))
                                .font(PPBrandFont.bold(size: 10))
                        }
                        .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.90))
                                .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.opacity.combined(with: .scale))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 9))
                        Text(Language.get("PhysicalSpec_3D_DragHint", alter: "اسحب للتدوير 3D"))
                            .font(PPBrandFont.medium(size: 9.5))
                    }
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .padding(6)
                }
            }
        }
    }
}

// MARK: - Category-Defining Dimensions Measurement Chamber

private struct PPDimensionsMeasureChamber: View {
    @Binding var widthText: String
    @Binding var heightText: String
    @Binding var unit: String
    let isIPad: Bool

    @FocusState private var isWidthFocused: Bool
    @FocusState private var isHeightFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let availableUnits: [String] = ["cm", "m", "in", "mm"]

    private var parsedWidth: Double {
        Double(widthText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var parsedHeight: Double {
        Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private let cagePresets: [PPCageDimensionPreset] = [
        PPCageDimensionPreset(id: "small", width: 40, height: 30, unit: "cm", label: "40 × 30", targetPet: Language.get("Pet_BirdsHamsters", alter: "طيور وقوارض")),
        PPCageDimensionPreset(id: "med", width: 60, height: 40, unit: "cm", label: "60 × 40", targetPet: Language.get("Pet_CatsRabbits", alter: "قطط وأرانب")),
        PPCageDimensionPreset(id: "large", width: 80, height: 50, unit: "cm", label: "80 × 50", targetPet: Language.get("Pet_SmallDogs", alter: "كلاب صغيرة")),
        PPCageDimensionPreset(id: "xlarge", width: 100, height: 70, unit: "cm", label: "100 × 70", targetPet: Language.get("Pet_MedDogs", alter: "كلاب متوسطة")),
        PPCageDimensionPreset(id: "jumbo", width: 120, height: 80, unit: "cm", label: "120 × 80", targetPet: Language.get("Pet_AviaryLarge", alter: "أقفاص كبيرة"))
    ]

    private func swapDimensions() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            let temp = widthText
            widthText = heightText
            heightText = temp
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Live 2D Architectural Blueprint Canvas
            PPDimensionsBlueprintCanvas(
                width: parsedWidth,
                height: parsedHeight,
                unit: unit,
                isIPad: isIPad
            )

            // Dual Precision Sculpted Input Fields + Central Swap Button
            HStack(spacing: 8) {
                // Width Input Field
                dimensionInputField(
                    title: Language.get("PhysicalSpec_Width", alter: "العرض"),
                    icon: "arrow.left.and.right",
                    text: $widthText,
                    isFocused: $isWidthFocused
                )

                // Tactical Swap Affordance (⇄)
                Button {
                    swapDimensions()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.35), lineWidth: 1.0)
                            )
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                    }
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(Language.get("PhysicalSpec_Swap", alter: "تبديل العرض والارتفاع"))

                // Height Input Field
                dimensionInputField(
                    title: Language.get("PhysicalSpec_Height", alter: "الارتفاع"),
                    icon: "arrow.up.and.down",
                    text: $heightText,
                    isFocused: $isHeightFocused
                )
            }

            // Unit Selector Dock (cm, m, in, mm)
            HStack(spacing: 6) {
                Text(Language.get("Unit", alter: "الوحدة:"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 4) {
                    ForEach(availableUnits, id: \.self) { u in
                        let isSelected = unit.lowercased() == u.lowercased()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.80)) {
                                unit = u
                            }
                        } label: {
                            Text(localizedUnitName(u))
                                .font(PPBrandFont.bold(size: 12))
                                .foregroundStyle(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.45, blue: 0.95))
                                        : AdminSurface.primaryText.opacity(0.80)
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(
                                            isSelected
                                                ? Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.35 : 0.15)
                                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.60) : Color.clear,
                                            lineWidth: 0.9
                                        )
                                )
                        }
                        .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                    }
                }
            }

            // Cage & Enclosure Quick Presets Runway
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("PhysicalSpec_Presets_Cages", alter: "مقاسات شائعة للأقفاص والنواقل:"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cagePresets) { preset in
                            let isCurrentMatch = abs(parsedWidth - preset.width) < 0.01 && abs(parsedHeight - preset.height) < 0.01 && unit.caseInsensitiveCompare(preset.unit) == .orderedSame
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                    widthText = String(format: "%g", preset.width)
                                    heightText = String(format: "%g", preset.height)
                                    unit = preset.unit
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 3) {
                                        Text(verbatim: preset.label.normalizedEnglishDigits)
                                            .font(PPBrandFont.bold(size: 12))
                                        Text(localizedUnitName(preset.unit))
                                            .font(PPBrandFont.medium(size: 10))
                                    }
                                    .foregroundStyle(
                                        isCurrentMatch
                                            ? (colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.45, blue: 0.95))
                                            : AdminSurface.primaryText.opacity(0.85)
                                    )

                                    Text(preset.targetPet)
                                        .font(AdminType.caption2)
                                        .foregroundStyle(
                                            isCurrentMatch
                                                ? Color(red: 0.20, green: 0.50, blue: 0.95)
                                                : AdminSurface.secondaryText
                                        )
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            isCurrentMatch
                                                ? Color(red: 0.20, green: 0.50, blue: 0.95).opacity(colorScheme == .dark ? 0.30 : 0.12)
                                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isCurrentMatch ? Color(red: 0.20, green: 0.50, blue: 0.95).opacity(0.60) : Color.clear,
                                            lineWidth: 1.0
                                        )
                                )
                            }
                            .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func dimensionInputField(
        title: String,
        icon: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.95))
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            HStack(spacing: 6) {
                TextField("0.0", text: text)
                    .font(PPBrandFont.bold(size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
                    .keyboardType(.decimalPad)
                    .focused(isFocused)
                    .onChange(of: text.wrappedValue) { val in
                        let clean = val.normalizedEnglishDigits(allowsDecimal: true)
                        if clean != val {
                            text.wrappedValue = clean
                        }
                    }

                if !text.wrappedValue.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused.wrappedValue
                            ? Color(red: 0.20, green: 0.50, blue: 0.95)
                            : AdminSurface.hairline.opacity(0.85),
                        lineWidth: isFocused.wrappedValue ? 1.5 : 0.75
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func localizedUnitName(_ u: String) -> String {
        switch u.lowercased() {
        case "cm": return Language.get("PhysicalSpec_Unit_cm", alter: "سم")
        case "m": return Language.get("PhysicalSpec_Unit_m", alter: "م")
        case "in": return Language.get("PhysicalSpec_Unit_in", alter: "بوصة")
        case "mm": return Language.get("PhysicalSpec_Unit_mm", alter: "ملم")
        default: return u
        }
    }
}

// MARK: - Category-Defining Physical Specification Segmented Switcher (iPhone)

private struct PPPhysicalSpecSegmentedDeck: View {
    @Binding var selectedMode: PPPhysicalSpecMode

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let selectableModes: [PPPhysicalSpecMode] = [
        .dimensions, .standardSize, .weightVolume
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(selectableModes) { mode in
                let isSelected = selectedMode == mode
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        if selectedMode == mode {
                            selectedMode = .none
                        } else {
                            selectedMode = mode
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11.5, weight: .bold))

                        Text(mode.shortTitle)
                            .font(PPBrandFont.bold(size: 12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .foregroundStyle(
                        isSelected
                            ? (colorScheme == .dark ? Color.white : AdminSurface.primary)
                            : AdminSurface.secondaryText
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isSelected
                                    ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.35 : 0.14)
                                    : Color.clear
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? AdminSurface.primary.opacity(0.60) : Color.clear,
                                lineWidth: 1.0
                            )
                    )
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.70), lineWidth: 0.75)
        )
    }
}

// MARK: - Category-Defining Physical Specification Zero / Prompt State

private struct PPPhysicalSpecZeroStateCard: View {
    let onSelectMode: (PPPhysicalSpecMode) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let quickModes: [PPPhysicalSpecMode] = [
        .dimensions, .standardSize, .weightVolume
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("PhysicalSpec_Subtitle", alter: "اختر نمط قياس واحداً للمنتج أو اتركه بدون تحديد"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(quickModes) { mode in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelectMode(mode)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)

                            Text(mode.shortTitle)
                                .font(PPBrandFont.bold(size: 11.5))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AdminSurface.control)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AdminSurface.hairline.opacity(0.75), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(mode.title)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.40), lineWidth: 0.75)
        )
    }
}

// MARK: - Dedicated Native iPhone Physical Specification Studio

private struct PPiPhonePhysicalSpecStudio: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel
    var onFocusChanged: ((Bool) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeModeBadgeText: String? {
        switch viewModel.physicalSpecMode {
        case .none: return nil
        case .dimensions: return Language.get("Dimensions_Short", alter: "الأبعاد W×H")
        case .standardSize: return Language.get("CatalogIntake_SizeLabel", alter: "المقاس")
        case .weightVolume: return Language.get("CatalogIntake_WeightLabel", alter: "الوزن/السعة")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Optional Tag + Active Mode Tag + Clear Button
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: viewModel.physicalSpecMode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 20)

                Text(Language.get("PhysicalSpec_Title", alter: "المواصفات الفيزيائية للصنف"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("CatalogIntake_Optional", alter: "(اختياري)"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer(minLength: 4)

                // Active Mode Tag with Quick Clear
                if let badgeText = activeModeBadgeText {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(verbatim: badgeText)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                viewModel.physicalSpecMode = .none
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.30), lineWidth: 0.75))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // 3-Mode Tactile Sliding Segmented Deck
            PPPhysicalSpecSegmentedDeck(
                selectedMode: $viewModel.physicalSpecMode
            )

            // Active Chamber Studio
            Group {
                switch viewModel.physicalSpecMode {
                case .dimensions:
                    PPDimensionsMeasureChamber(
                        widthText: $viewModel.dimensionWidthText,
                        heightText: $viewModel.dimensionHeightText,
                        unit: $viewModel.dimensionUnit,
                        isIPad: false
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .standardSize:
                    PPAccessorySizeSelector(
                        size: $viewModel.size
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .weightVolume:
                    PPAccessoryUnifiedMeasureChamber(
                        weightText: $viewModel.weightText,
                        weightUnit: $viewModel.weightUnit,
                        onFocusChanged: onFocusChanged
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .none:
                    PPPhysicalSpecZeroStateCard(
                        onSelectMode: { mode in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                viewModel.physicalSpecMode = mode
                            }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .opacity)
                }
            }
        }
    }
}

// MARK: - Dedicated Native iPad Physical Specification Studio

private struct PPiPadPhysicalSpecStudio: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel
    var onFocusChanged: ((Bool) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let selectableModes: [PPPhysicalSpecMode] = [
        .dimensions, .standardSize, .weightVolume
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header with Large Title + Keyboard Shortcuts Telemetry + Clear Affordance
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.get("PhysicalSpec_Title", alter: "المواصفات الفيزيائية للصنف"))
                            .font(PPBrandFont.bold(size: 17))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("CatalogIntake_Optional", alter: "(اختياري)"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Text(Language.get("PhysicalSpec_Subtitle", alter: "اختر نمط قياس واحداً للمنتج أو اتركه بدون تحديد"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                if viewModel.physicalSpecMode != .none {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                            viewModel.physicalSpecMode = .none
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text(Language.get("PhysicalSpec_Clear", alter: "مسح التحديد"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.control, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }

            // Widescreen 3-Card Tactical Archetype Deck
            HStack(spacing: 12) {
                ForEach(selectableModes) { mode in
                    let isSelected = viewModel.physicalSpecMode == mode
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            if viewModel.physicalSpecMode == mode {
                                viewModel.physicalSpecMode = .none
                            } else {
                                viewModel.physicalSpecMode = mode
                            }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? AdminSurface.primary.opacity(0.20)
                                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                    )
                                    .frame(width: 36, height: 36)

                                Image(systemName: mode.symbol)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(
                                        isSelected ? AdminSurface.primary : AdminSurface.secondaryText
                                    )
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(mode.title)
                                        .font(PPBrandFont.bold(size: 13.5))
                                        .foregroundStyle(
                                            isSelected ? AdminSurface.primaryText : AdminSurface.primaryText.opacity(0.85)
                                        )
                                        .lineLimit(1)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(AdminSurface.primary)
                                    }
                                }

                                Text(mode.subtitle)
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    isSelected
                                        ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.22 : 0.08)
                                        : AdminSurface.control
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? AdminSurface.primary.opacity(0.75)
                                        : AdminSurface.hairline.opacity(0.70),
                                    lineWidth: isSelected ? 1.5 : 0.75
                                )
                        )
                        .shadow(
                            color: isSelected ? AdminSurface.primary.opacity(0.12) : Color.clear,
                            radius: 8,
                            x: 0,
                            y: 2
                        )
                    }
                    .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
                    .hoverEffect(.lift)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                }
            }

            // Widescreen Active Content Stage
            Group {
                switch viewModel.physicalSpecMode {
                case .dimensions:
                    PPDimensionsMeasureChamber(
                        widthText: $viewModel.dimensionWidthText,
                        heightText: $viewModel.dimensionHeightText,
                        unit: $viewModel.dimensionUnit,
                        isIPad: true
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .standardSize:
                    PPAccessorySizeSelector(
                        size: $viewModel.size
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .weightVolume:
                    PPAccessoryUnifiedMeasureChamber(
                        weightText: $viewModel.weightText,
                        weightUnit: $viewModel.weightUnit,
                        onFocusChanged: onFocusChanged
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                case .none:
                    PPPhysicalSpecZeroStateCard(
                        onSelectMode: { mode in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                viewModel.physicalSpecMode = mode
                            }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .opacity)
                }
            }
        }
    }
}

// MARK: - Category-Defining Physical Specification Orchestrator

private struct PPPhysicalSpecOrchestrator: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel
    var onFocusChanged: ((Bool) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if isIPad {
                PPiPadPhysicalSpecStudio(
                    viewModel: viewModel,
                    onFocusChanged: onFocusChanged
                )
            } else {
                PPiPhonePhysicalSpecStudio(
                    viewModel: viewModel,
                    onFocusChanged: onFocusChanged
                )
            }
        }
    }
}

// MARK: - Category-Defining Expiry & Shelf-Life Sentinel

private struct PPAccessoryExpirySentinel: View {
    @Binding var hasExpiryDate: Bool
    @Binding var expiryDate: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: expiryDate)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day ?? 0
    }

    private var shelfLifeHealth: (text: String, color: Color, icon: String) {
        let days = daysRemaining
        if days < 0 {
            return (Language.get("Expiry_Expired", alter: "منتهي الصلاحية!"), Color(uiColor: .ppError), "exclamationmark.octagon.fill")
        } else if days < 30 {
            return (String(format: Language.get("Expiry_Urgent_Days", alter: "تنبيه: متبقي %ld يوماً فقط"), days).normalizedEnglishDigits, Color(uiColor: .ppError), "exclamationmark.triangle.fill")
        } else if days <= 90 {
            let months = max(1, days / 30)
            return (String(format: Language.get("Expiry_Moderate_Months", alter: "صلاحية متوسطة (متبقي %ld أشهر)"), months).normalizedEnglishDigits, Color(red: 0.96, green: 0.62, blue: 0.15), "clock.badge.exclamationmark.fill")
        } else {
            let months = days / 30
            return (String(format: Language.get("Expiry_Excellent_Months", alter: "صلاحية ممتازة (متبقي %ld شهراً)"), months).normalizedEnglishDigits, Color(red: 0.06, green: 0.72, blue: 0.51), "checkmark.seal.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Master Toggle Row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            hasExpiryDate
                                ? AdminSurface.primary.opacity(colorScheme == .dark ? 0.28 : 0.12)
                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                        .frame(width: 38, height: 38)

                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(hasExpiryDate ? AdminSurface.primary : AdminSurface.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CatalogIntake_ExpiryToggle", alter: "للصنف تاريخ انتهاء صلاحية"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("CatalogIntake_ExpiryHint", alter: "فعّلها عندما تكون الصلاحية مطبوعة على العبوة لحساب دورة الصلاحية."))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: $hasExpiryDate)
                    .labelsHidden()
                    .tint(AdminSurface.primary)
            }

            if hasExpiryDate {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().background(AdminSurface.hairline)

                    // Freshness Gauge Pill
                    let health = shelfLifeHealth
                    HStack(spacing: 6) {
                        Image(systemName: health.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(health.color)

                        Text(health.text)
                            .font(AdminType.captionBold)
                            .foregroundStyle(health.color)

                        Spacer()

                        Text(verbatim: expiryDateFormatted.normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 12))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(health.color.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(health.color.opacity(0.30), lineWidth: 0.75)
                    )

                    // Quick Shelf-Life Extension Presets
                    HStack(spacing: 6) {
                        shelfLifePresetButton(label: "+6 أشهر".normalizedEnglishDigits, months: 6)
                        shelfLifePresetButton(label: "+سنة", months: 12)
                        shelfLifePresetButton(label: "+سنتين", months: 24)
                        shelfLifePresetButton(label: "+3 سنوات", months: 36)
                    }

                    // Native Compact DatePicker
                    HStack {
                        Label(Language.get("CatalogIntake_ExpiryDate", alter: "تاريخ انتهاء الصلاحية"), systemImage: "calendar")
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Spacer()

                        DatePicker(
                            "",
                            selection: $expiryDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    hasExpiryDate
                        ? AdminSurface.primary.opacity(0.35)
                        : AdminSurface.hairline.opacity(0.70),
                    lineWidth: 0.8
                )
        )
    }

    private var expiryDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        return formatter.string(from: expiryDate)
    }

    private func shelfLifePresetButton(label: String, months: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let newDate = Calendar.current.date(byAdding: .month, value: months, to: Date()) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                    expiryDate = newDate
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.30), lineWidth: 0.75))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: reduceMotion))
    }
}

// MARK: - Accessory & Food Task-Led Catalog Journey

private struct PPAccessoryFoodIntakeJourney: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: FocusedField?

    @State private var stageMessage: String?
    @State private var previewMedia: PPLivePetPreviewMedia?
    @State private var showQuantityAlert: Bool = false
    @State private var quantityAlertText: String = ""
    @State private var bilingualLanguage: PPBilingualLanguage = .arabic
    @State private var showStepsAppSwitcher: Bool = false

    private enum FocusedField: Hashable {
        case name
        case description
        case sku
        case barcode
        case weight
        case price
        case costPrice
        case discountPercent
        case discountAmount
        case wholesalePrice
    }

    var body: some View {
        ZStack {
            catalogBackground

            VStack(spacing: 0) {
                catalogHeader
                    .background(
                        AdminSurface.background
                            .ignoresSafeArea(edges: .top)
                    )
                    .accessibilitySortPriority(4)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: AdminSpacing.base) {
                            catalogCompass
                                .accessibilitySortPriority(3)
                            catalogFeedback
                            catalogStageScene
                                .id(viewModel.activeStage)
                                .transition(
                                    accessibilityReduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                                )
                                .accessibilitySortPriority(2)
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.xs)
                        .padding(.bottom, 140)
                    }
                    .scrollDismissesKeyboardCompat()
                    .onChange(of: focusedField) { field in
                        scrollToFocusedField(proxy: proxy, targetField: field)
                    }
                    .onChange(of: bilingualLanguage) { _ in
                        scrollToFocusedField(proxy: proxy)
                    }
                }
                .id(viewModel.activeStage)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                catalogActionDock
                    .accessibilitySortPriority(1)
            }
            .scaleEffect(showStepsAppSwitcher ? 0.83 : 1.0)
            .blur(radius: showStepsAppSwitcher ? 2.5 : 0.0)
            .clipShape(RoundedRectangle(cornerRadius: showStepsAppSwitcher ? 36 : 0, style: .continuous))
            .shadow(
                color: Color.black.opacity(showStepsAppSwitcher ? 0.32 : 0.0),
                radius: showStepsAppSwitcher ? 28 : 0,
                y: showStepsAppSwitcher ? 14 : 0
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showStepsAppSwitcher)
            .allowsHitTesting(!showStepsAppSwitcher && !viewModel.isSubmitting && !viewModel.hasCompletedSave)
            .disabled(viewModel.hasCompletedSave)
            .accessibilityHidden(viewModel.isSubmitting || showStepsAppSwitcher)

            if showStepsAppSwitcher {
                catalogStepsAppSwitcherOverlay
                    .transition(
                        accessibilityReduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 1.06)),
                                removal: .opacity.combined(with: .scale(scale: 0.94))
                            )
                    )
                    .zIndex(50)
            }

            if viewModel.isSubmitting {
                catalogSubmissionOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.showImagePicker) {
            PPLivePetPhotoPicker(maxSelection: max(0, 9 - viewModel.totalImageCount)) { images, failedCount in
                viewModel.addPickedImages(images)
                guard failedCount > 0 else { return }
                let message = String(
                    format: tr("CatalogIntake_PhotoImportFailureFormat", "تعذر استيراد %ld من الصور المحددة. أعد المحاولة للصور الناقصة."),
                    failedCount
                )
                stageMessage = message
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        .sheet(isPresented: $viewModel.showSpeciesPicker) {
            PPCatalogMultiChoiceSheet(
                title: tr("CatalogIntake_SelectCategory", "اختر فئات الحيوانات"),
                subtitle: tr("CatalogIntake_SelectCategorySub", "اختر فئة واحدة أو عدة فئات، أو حدد جميع الفئات."),
                searchPrompt: tr("CatalogIntake_SearchCategory", "ابحث عن فئة"),
                allOptionTitle: tr("CatalogIntake_AllCategoriesPrompt", "جميع الفئات • مناسب لكل الحيوانات"),
                allOptionSubtitle: tr("CatalogIntake_AllCategoriesSub", "مناسب للكلاب، القطط، الطيور، وجميع الحيوانات الأليفة"),
                allOptionSymbol: "globe",
                choices: viewModel.availableMainKinds.map { kind in
                    PPLivePetChoice(
                        id: String(kind.id),
                        title: kind.kindName,
                        subtitle: String(
                            format: tr("CatalogIntake_SubcategoryCount", "%ld تصنيفاً فرعياً"),
                            (kind.subKindsArray as? [SubKindModel])?.count ?? 0
                        ),
                        symbol: viewModel.isFood ? "fork.knife.circle.fill" : "shippingbox.fill"
                    )
                },
                isAllSelected: $viewModel.isAllCategoriesSelected,
                selectedIDs: Binding(
                    get: { Set(viewModel.selectedMainKinds.map { String($0) }) },
                    set: { newSet in
                        viewModel.selectedMainKinds = Set(newSet.compactMap { Int($0) })
                    }
                ),
                onRefresh: {
                    viewModel.loadMainKinds(forceServer: true)
                },
                onConfirm: {
                    if viewModel.isAllCategoriesSelected {
                        viewModel.selectedMainKind = nil
                    } else if let firstID = viewModel.selectedMainKinds.first {
                        viewModel.selectedMainKind = viewModel.availableMainKinds.first(where: { $0.id == firstID })
                    }
                    viewModel.fetchFreshSubKindsForSelectedCategories()
                }
            )
            .onAppear {
                viewModel.loadMainKinds(forceServer: true)
            }
        }
        .sheet(isPresented: $viewModel.showBreedPicker) {
            PPCatalogMultiChoiceSheet(
                title: tr("CatalogIntake_SelectSubcategory", "اختر التصنيفات الفرعية"),
                subtitle: tr("CatalogIntake_SelectSubcategorySub", "اختر تصنيفاً واحداً أو عدة تصنيفات، أو حدد جميع التصنيفات."),
                searchPrompt: tr("CatalogIntake_SearchSubcategory", "ابحث عن تصنيف فرعي"),
                allOptionTitle: tr("CatalogIntake_AllSubcategoriesPrompt", "جميع السلالات والتصنيفات الفرعية"),
                allOptionSubtitle: tr("CatalogIntake_AllSubcategoriesSub", "شامل لكل السلالات والتفريعات بدون استثناء"),
                allOptionSymbol: "tag.fill",
                choices: viewModel.availableSubKinds.map { subkind in
                    let parentCategoryName = viewModel.availableMainKinds.first(where: { $0.id == subkind.mainKindID })?.kindName
                        ?? viewModel.availableMainKinds.first(where: { ($0.subKindsArray as? [SubKindModel])?.contains(where: { $0.id == subkind.id }) == true })?.kindName
                    let showSection = (viewModel.selectedMainKinds.count > 1 || viewModel.isAllCategoriesSelected)
                    return PPLivePetChoice(
                        id: String(subkind.id),
                        title: subkind.subKindName,
                        subtitle: showSection ? parentCategoryName : nil,
                        symbol: "tag.fill",
                        sectionHeader: showSection ? parentCategoryName : nil
                    )
                },
                isAllSelected: $viewModel.isAllSubCategoriesSelected,
                selectedIDs: Binding(
                    get: { Set(viewModel.selectedSubKinds.map { String($0) }) },
                    set: { newSet in
                        viewModel.selectedSubKinds = Set(newSet.compactMap { Int($0) })
                    }
                ),
                onRefresh: {
                    viewModel.fetchFreshSubKindsForSelectedCategories()
                },
                onConfirm: {
                    if viewModel.isAllSubCategoriesSelected {
                        viewModel.selectedSubKind = nil
                    } else if let firstID = viewModel.selectedSubKinds.first {
                        viewModel.selectedSubKind = viewModel.availableSubKinds.first(where: { $0.id == firstID })
                    }
                }
            )
            .onAppear {
                viewModel.fetchFreshSubKindsForSelectedCategories()
            }
        }
        .sheet(isPresented: $viewModel.showStorePicker) {
            PPBranchSelectionGateView(
                title: tr("CatalogIntake_SelectStore", "اختر الفرع المالك"),
                subtitle: tr("CatalogIntake_SelectStoreSub", "سيُنسب الصنف والمخزون إلى هذا الفرع."),
                selectedBranchID: viewModel.selectedStoreID,
                allowGlobalAccess: false
            ) { selectedBranch in
                viewModel.selectedStoreID = selectedBranch.branchID
                viewModel.selectedStoreName = selectedBranch.localizedName()
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $viewModel.showQuantityGroupInspector) {
            if let group = viewModel.selectedQuantityGroupForEditing {
                PPQuantityGroupInspectorSheet(
                    group: group,
                    canManageWholesale: viewModel.canManageWholesale,
                    onSave: { updated in
                        viewModel.saveQuantityGroup(updated)
                    },
                    onDelete: viewModel.quantityGroups.count > 1 ? {
                        viewModel.deleteQuantityGroup(id: group.id)
                    } : nil
                )
            }
        }
        .fullScreenCover(item: $previewMedia) { media in
            PPLivePetMediaPreview(media: media)
        }
        .onChange(of: viewModel.isSubmitting) { submitting in
            guard submitting else { return }
            UIAccessibility.post(
                notification: .screenChanged,
                argument: tr("CatalogIntake_Submitting", "جارٍ حفظ الصنف بأمان")
            )
        }
        .onChange(of: viewModel.errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .onChange(of: viewModel.saveSuccessMessage) { message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func promptQuantityEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: tr("EditQuantity", "تعديل الكمية"),
            subtitle: tr("EnterQuantityPrompt", "أدخل كمية المخزون المتاحة لهذا الصنف"),
            placeholder: tr("CatalogIntake_Quantity", "الكمية المتاحة"),
            initialText: "\(viewModel.quantity)",
            confirmText: tr("Save", "حفظ"),
            cancelText: tr("Cancel", "إلغاء"),
            secureEntry: false,
            keyboardType: .numberPad
        ) { text in
            guard let text else { return }
            let normalized = text.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(normalized) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    viewModel.quantity = max(0, val)
                }
            }
        }
    }

    private var catalogBackground: some View {
        AdminSurface.background
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .accessibilityHidden(true)
    }

    private var catalogHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            Button {
                if viewModel.hasUnsavedChanges {
                    showCatalogDiscardAlert()
                } else {
                    viewModel.discardChangesAndDismiss()
                }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(AdminSurface.hairline.opacity(0.8), lineWidth: 0.75)
                    )
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .accessibilityLabel(tr("Back", "رجوع"))
            .accessibilityHint(viewModel.hasUnsavedChanges
                ? tr("CatalogIntake_BackUnsavedHint", "يعرض تأكيداً قبل تجاهل التعديلات")
                : tr("CatalogIntake_BackHint", "يعود إلى قائمة الكتالوج"))

            VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                Text(catalogScreenTitle)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                HStack(spacing: AdminSpacing.xs) {
                    Circle()
                        .fill(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                        .frame(width: 6, height: 6)
                    Text(viewModel.isDraft
                        ? tr("CatalogIntake_DraftState", "مسودة غير ظاهرة")
                        : tr("CatalogIntake_ActiveState", "جاهز للإتاحة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer(minLength: AdminSpacing.xs)

            Button {
                focusedField = nil
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    showStepsAppSwitcher.toggle()
                }
            } label: {
                Image(systemName: viewModel.isFood ? "fork.knife" : "shippingbox.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(showStepsAppSwitcher ? Color.white : AdminSurface.primary)
                    .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
                    .background(
                        showStepsAppSwitcher ? AdminSurface.primary : AdminSurface.primary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(
                                showStepsAppSwitcher ? AdminSurface.primary.opacity(0.8) : AdminSurface.primary.opacity(0.25),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(
                        color: AdminSurface.primary.opacity(showStepsAppSwitcher ? 0.35 : 0.0),
                        radius: 8,
                        y: 3
                    )
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .accessibilityLabel(tr("CatalogIntake_StepsSwitcherTitle", "مراحل إضافة الصنف"))
            .accessibilityHint(tr("CatalogIntake_StepsSwitcherHint", "يفتح نظرة عامة لجميع الخطوات بنمط مبدل تطبيقات الآيفون"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.sm)
        .background(Color.clear)
    }

    private var catalogCompass: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(stageEyebrow(viewModel.activeStage).uppercased())
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                    Text(stageTitle(viewModel.activeStage))
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(stageQuestion(viewModel.activeStage))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AdminSpacing.sm)
                Text(String(
                    format: tr("CatalogIntake_CompletedFormat", "%ld من 4 مكتملة"),
                    completedStageCount
                ))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, AdminSpacing.sm)
                .frame(minHeight: 28)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.xs) {
                    ForEach(PPEditorStage.allCases) { stage in
                        Button {
                            move(to: stage)
                        } label: {
                            stagePill(for: stage)
                        }
                        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                        .accessibilityAddTraits(stage == viewModel.activeStage ? .isSelected : [])
                    }
                }
            }
        }
        .padding(AdminSpacing.base)
        .background(
            LinearGradient(
                colors: [AdminSurface.surface, AdminSurface.primarySoft.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stagePill(for stage: PPEditorStage) -> some View {
        let isCurrent = stage == viewModel.activeStage
        let isDone = validationMessage(for: stage) == nil
        let icon = isDone ? "checkmark.circle.fill" : stage.symbol
        let tint = progressColor(for: stage)
        HStack(spacing: AdminSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(shortStageTitle(stage))
                .font(AdminType.caption2Bold)
                .lineLimit(1)
        }
        .foregroundStyle(isCurrent ? Color.white : tint)
        .padding(.horizontal, AdminSpacing.sm)
        .frame(minHeight: 36)
        .background(
            isCurrent ? AdminSurface.primary : tint.opacity(0.10),
            in: Capsule()
        )
    }

    @ViewBuilder
    private var catalogFeedback: some View {
        if let error = viewModel.errorMessage, !error.isEmpty {
            catalogBanner(
                message: error,
                symbol: "exclamationmark.triangle.fill",
                color: Color(uiColor: .ppError),
                dismiss: { viewModel.errorMessage = nil }
            )
        } else if let message = stageMessage, !message.isEmpty {
            catalogBanner(
                message: message,
                symbol: "arrow.down.circle.fill",
                color: Color(uiColor: .ppWarning),
                dismiss: { stageMessage = nil }
            )
        } else if let success = viewModel.saveSuccessMessage, !success.isEmpty {
            catalogBanner(
                message: success,
                symbol: "checkmark.seal.fill",
                color: Color(uiColor: .ppSuccess),
                dismiss: nil
            )
        }
    }

    private func catalogBanner(
        message: String,
        symbol: String,
        color: Color,
        dismiss: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                }
                .accessibilityLabel(tr("Close", "إغلاق"))
            }
        }
        .padding(AdminSpacing.md)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var catalogStageScene: some View {
        switch viewModel.activeStage {
        case .identity:
            identityScene
        case .bioVault:
            specificationsScene
        case .pricing:
            pricingScene
        case .governance:
            releaseScene
        }
    }

    private var identityScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("CatalogIntake_IdentityEyebrow", "الهوية المرئية"),
            title: tr("CatalogIntake_IdentityTitle", "عرّف الصنف كما سيظهر للفريق والعملاء"),
            subtitle: tr("CatalogIntake_IdentitySubtitle", "أضف الصور والاسم والوصف أولاً. الاسم مطلوب، ويمكن تحسين بقية المحتوى لاحقاً."),
            symbol: "photo.on.rectangle.angled"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                mediaCanvas

                Divider().background(AdminSurface.hairline)

                PPBilingualInputField(
                    title: tr("CatalogIntake_NameLabel", "اسم الصنف"),
                    isRequired: true,
                    arabicText: $viewModel.name,
                    englishText: $viewModel.nameEn,
                    arabicPlaceholder: tr("CatalogIntake_NamePlaceholder", "مثال: منتج واضح وسهل البحث"),
                    englishPlaceholder: "e.g. Premium Grain-Free Cat Food",
                    selectedLanguage: $bilingualLanguage,
                    isFocused: focusedField == .name,
                    onFocusChange: { focused in
                        if focused { focusedField = .name }
                        else if focusedField == .name { focusedField = nil }
                    },
                    onSubmit: { focusedField = .description }
                )
                .id(FocusedField.name)

                PPBilingualTextEditorField(
                    title: tr("CatalogIntake_DescriptionLabel", "الوصف"),
                    isRequired: false,
                    arabicText: $viewModel.desc,
                    englishText: $viewModel.descEn,
                    arabicPlaceholder: tr("CatalogIntake_DescriptionPlaceholder", "المزايا، الاستخدام، المقاس أو المعلومات المهمة للعميل…"),
                    englishPlaceholder: "Key features, directions for use, size, ingredients…",
                    selectedLanguage: $bilingualLanguage,
                    minHeight: 120,
                    isFocused: focusedField == .description,
                    onFocusChange: { focused in
                        if focused { focusedField = .description }
                        else if focusedField == .description { focusedField = nil }
                    }
                )
                .id(FocusedField.description)

                HStack(spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                        fieldLabel(tr("CatalogIntake_SKULabel", "رمز المنتج (SKU)"), required: false)
                        TextField(tr("CatalogIntake_SKUPlaceholder", "مثال: PP-10023"), text: $viewModel.sku)
                            .font(AdminType.body)
                            .focused($focusedField, equals: .sku)
                            .environment(\.layoutDirection, .leftToRight)
                            .padding(.horizontal, AdminSpacing.md)
                            .frame(minHeight: AdminTouchTarget.expanded)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                            .overlay(fieldFocusBorder(focusedField == .sku))
                    }

                    VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                        fieldLabel(tr("CatalogIntake_BarcodeLabel", "الباركود"), required: false)
                        HStack(spacing: AdminSpacing.xs) {
                            TextField(tr("CatalogIntake_BarcodePlaceholder", "امسح أو اكتب الباركود"), text: $viewModel.barcode)
                                .font(AdminType.body)
                                .englishNumericInput(text: $viewModel.barcode, allowsDecimal: false)
                                .focused($focusedField, equals: .barcode)

                            if !viewModel.barcode.isEmpty {
                                Button {
                                    viewModel.barcode = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                        .frame(width: 30, height: AdminTouchTarget.minimum)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                            }

                            AdminBarcodeScanButton { scanned in
                                viewModel.barcode = scanned
                                focusedField = nil
                            }
                        }
                        .padding(.leading, AdminSpacing.md)
                        .padding(.trailing, AdminSpacing.xs)
                        .frame(minHeight: AdminTouchTarget.expanded)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .barcode))
                    }
                }
            }
        }
    }

    private var mediaCanvas: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .center, spacing: AdminSpacing.sm) {
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(tr("CatalogIntake_MediaTitle", "صور الكتالوج"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(
                        format: tr("CatalogIntake_PhotoCount", "%ld من 9 صور"),
                        viewModel.totalImageCount
                    ))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                if viewModel.canAddImages {
                    Button {
                        viewModel.showImagePicker = true
                    } label: {
                        Label(tr("CatalogIntake_AddPhotos", "إضافة صور"), systemImage: "photo.badge.plus")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, AdminSpacing.md)
                            .frame(height: 34)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                }
            }

            if viewModel.totalImageCount == 0 {
                Button {
                    viewModel.showImagePicker = true
                } label: {
                    VStack(spacing: AdminSpacing.sm) {
                        Image(systemName: viewModel.isFood ? "fork.knife.circle" : "shippingbox.circle")
                            .font(.system(size: 34, weight: .light))
                        Text(tr("CatalogIntake_EmptyMediaTitle", "ابدأ بصورة واضحة للصنف"))
                            .font(AdminType.headline)
                        Text(tr("CatalogIntake_EmptyMediaSubtitle", "يمكنك اختيار حتى 9 صور، وستصبح الصورة الأولى هي الرئيسية."))
                            .font(AdminType.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(AdminSurface.primary.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
                    )
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AdminSpacing.sm) {
                        ForEach(Array(viewModel.existingImageURLs.enumerated()), id: \.offset) { index, urlString in
                            remoteThumbnail(urlString: urlString, index: index)
                        }
                        ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, image in
                            localThumbnail(image: image, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func remoteThumbnail(urlString: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard let url = URL(string: urlString) else { return }
                previewMedia = PPLivePetPreviewMedia(source: .remote(url))
            } label: {
                AdminRemoteImage(url: URL(string: urlString), contentMode: .fill, targetSize: CGSize(width: 126, height: 126)) {
                    ProgressView().tint(AdminSurface.primary)
                }
                .frame(width: 126, height: 126)
                .background(AdminSurface.control)
                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay(primaryMediaBorder(index: index))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mediaPreviewLabel(index: index))
            .accessibilityHint(tr("CatalogIntake_PhotoPreviewButtonHint", "يفتح معاينة الصورة بملء الشاشة"))

            mediaRemoveButton(label: mediaRemoveLabel(index: index)) {
                viewModel.removeExistingImage(at: index)
            }
        }
    }

    private func localThumbnail(image: UIImage, index: Int) -> some View {
        let displayIndex = viewModel.existingImageURLs.count + index
        return ZStack(alignment: .topTrailing) {
            Button {
                previewMedia = PPLivePetPreviewMedia(source: .local(image))
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 126, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(primaryMediaBorder(index: displayIndex))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mediaPreviewLabel(index: displayIndex))
            .accessibilityHint(tr("CatalogIntake_PhotoPreviewButtonHint", "يفتح معاينة الصورة بملء الشاشة"))

            mediaRemoveButton(label: mediaRemoveLabel(index: displayIndex)) {
                viewModel.removePickedImage(at: index)
            }
        }
    }

    private func primaryMediaBorder(index: Int) -> some View {
        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            .strokeBorder(index == 0 ? AdminSurface.primary : AdminSurface.hairline, lineWidth: index == 0 ? 2 : 0.75)
            .overlay(alignment: .bottomLeading) {
                if index == 0 {
                    Text(tr("CatalogIntake_PrimaryPhoto", "الصورة الرئيسية"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AdminSpacing.sm)
                        .frame(minHeight: 24)
                        .background(AdminSurface.primary, in: Capsule())
                        .padding(AdminSpacing.xs)
                }
            }
    }

    private func mediaRemoveButton(label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.68), in: Circle())
        }
        .padding(6)
        .accessibilityLabel(label)
    }

    private func mediaPreviewLabel(index: Int) -> String {
        if index == 0 {
            return tr("CatalogIntake_PrimaryPhotoAccessibility", "الصورة 1، الصورة الرئيسية للكتالوج")
        }
        return String(
            format: tr("CatalogIntake_PhotoNumberAccessibility", "صورة الكتالوج %ld"),
            index + 1
        )
    }

    private func mediaRemoveLabel(index: Int) -> String {
        if index == 0 {
            return tr("CatalogIntake_RemovePrimaryPhoto", "إزالة الصورة الرئيسية")
        }
        return String(
            format: tr("CatalogIntake_RemovePhotoNumber", "إزالة الصورة %ld"),
            index + 1
        )
    }

    private var specificationsScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("CatalogIntake_SpecsEyebrow", "التصنيف والمواصفات"),
            title: viewModel.isFood
                ? tr("CatalogIntake_FoodSpecsTitle", "ثبّت فئة الغذاء وحجم العبوة وصلاحيتها")
                : tr("CatalogIntake_AccessorySpecsTitle", "ثبّت الفئة والحالة والمقاس"),
            subtitle: tr("CatalogIntake_SpecsSubtitle", "هذه البيانات تساعد الفريق والعملاء على العثور على الصنف الصحيح واتخاذ قرار دقيق."),
            symbol: "slider.horizontal.3"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                taxonomyButton(
                    title: tr("CatalogIntake_CategoryLabel", "الفئة الرئيسية"),
                    value: viewModel.selectedCategoryDisplayTitle,
                    placeholder: tr("CatalogIntake_CategoryPlaceholder", "اختر الفئة المطلوبة"),
                    symbol: viewModel.isFood ? "fork.knife" : "shippingbox",
                    required: true,
                    disabled: viewModel.isLoadingKinds
                ) {
                    viewModel.showSpeciesPicker = true
                }

                taxonomyButton(
                    title: tr("CatalogIntake_SubcategoryLabel", "التصنيف الفرعي"),
                    value: viewModel.selectedSubCategoryDisplayTitle,
                    placeholder: viewModel.hasNoCategorySelected
                        ? tr("CatalogIntake_SelectCategoryFirst", "اختر الفئة الرئيسية أولاً")
                        : tr("CatalogIntake_SubcategoryPlaceholder", "اختياري"),
                    symbol: "tag",
                    required: false,
                    disabled: viewModel.hasNoCategorySelected
                ) {
                    viewModel.showBreedPicker = true
                }

                if viewModel.isLoadingKinds {
                    HStack(spacing: AdminSpacing.sm) {
                        ProgressView()
                        Text(tr("CatalogIntake_LoadingCategories", "جارٍ تحميل الفئات…"))
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = viewModel.kindsErrorMessage, !error.isEmpty {
                    VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                        Text(error)
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(Color(uiColor: .ppError))
                        Button(tr("Retry", "إعادة المحاولة")) {
                            viewModel.loadMainKinds()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().background(AdminSurface.hairline)

                // Tactile Product Condition Matrix
                PPAccessoryConditionSelector(
                    condition: $viewModel.condition,
                    isFood: viewModel.isFood
                )

                if viewModel.isFood {
                    // Unified Physical Measurement Chamber (Food uses weight or volume)
                    PPAccessoryUnifiedMeasureChamber(
                        weightText: $viewModel.weightText,
                        weightUnit: $viewModel.weightUnit,
                        onFocusChanged: { focused in
                            if focused { focusedField = .weight }
                            else if focusedField == .weight { focusedField = nil }
                        }
                    )

                    // Expiry Date Sentinel (if food)
                    PPAccessoryExpirySentinel(
                        hasExpiryDate: $viewModel.hasExpiryDate,
                        expiryDate: $viewModel.expiryDate
                    )
                } else {
                    // Category-Defining Physical Specification Studio (Exclusive: Dimensions W×H vs Size vs Weight)
                    PPPhysicalSpecOrchestrator(
                        viewModel: viewModel,
                        onFocusChanged: { focused in
                            if focused { focusedField = .weight }
                            else if focusedField == .weight { focusedField = nil }
                        }
                    )
                }
            }
        }
    }

    private func taxonomyButton(
        title: String,
        value: String?,
        placeholder: String,
        symbol: String,
        required: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 42, height: 42)
                    .background(AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    HStack(spacing: 3) {
                        Text(title).font(AdminType.caption2Bold)
                        if required { Text("*").foregroundStyle(Color(uiColor: .ppError)) }
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                    Text((value?.isEmpty == false) ? value! : placeholder)
                        .font(AdminType.calloutBold)
                        .foregroundStyle((value?.isEmpty == false) ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: AdminSpacing.xs)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(disabled)
    }

    private var pricingScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("CatalogIntake_PricingEyebrow", "السعر والمخزون"),
            title: tr("CatalogIntake_PricingTitle", "حدّد سعر البيع والعرض والكمية"),
            subtitle: tr("CatalogIntake_PricingSubtitle", "السعر الأساسي مطلوب. الخصم اختياري، والكمية صفر تعني أن الصنف غير متوفر حالياً."),
            symbol: "tag.circle.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                moneyField(
                    title: tr("CatalogIntake_BasePrice", "السعر الأساسي (ر.ق)"),
                    text: $viewModel.priceText,
                    focus: .price,
                    required: true
                )

                moneyField(
                    title: tr("CatalogIntake_CostPrice", "سعر التكلفة (ر.ق)"),
                    text: $viewModel.costPriceText,
                    focus: .costPrice,
                    required: false
                )

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: AdminSpacing.md) {
                            discountPercentField
                            discountAmountField
                        }
                    } else {
                        HStack(spacing: AdminSpacing.md) {
                            discountPercentField
                            discountAmountField
                        }
                    }
                }

                HStack(alignment: .center, spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                        Text(tr("CatalogIntake_FinalPrice", "السعر النهائي"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(verbatim: String(format: "%.2f %@", viewModel.calculatedFinalPrice, tr("QAR", "ر.ق")).normalizedEnglishDigits)
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primary)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer()
                    Image(systemName: viewModel.discountPercent > 0 || viewModel.discountAmount > 0
                        ? "tag.fill"
                        : "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(viewModel.discountPercent > 0 || viewModel.discountAmount > 0
                            ? Color(uiColor: .ppWarning)
                            : Color(uiColor: .ppSuccess))
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

                wholesaleCard

                sellingUnitsCard

                Divider().background(AdminSurface.hairline)

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("CatalogIntake_Quantity", "الكمية المتاحة"), required: true)
                    HStack(spacing: AdminSpacing.md) {
                        quantityButton(symbol: "minus", enabled: viewModel.quantity > 0) {
                            viewModel.quantity = max(0, viewModel.quantity - 1)
                        }
                        Text(verbatim: viewModel.quantity.englishDigits)
                            .font(AdminType.title)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(String(
                                format: tr("CatalogIntake_QuantityAccessibility", "الكمية %ld"),
                                viewModel.quantity
                            ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptQuantityEdit()
                    }
                        quantityButton(symbol: "plus", enabled: true) {
                            viewModel.quantity += 1
                        }
                    }
                    .padding(AdminSpacing.sm)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                }
            }
        }
    }

    private var discountPercentField: some View {
        moneyField(
            title: tr("CatalogIntake_DiscountPercent", "نسبة الخصم (%)"),
            text: $viewModel.discountPercentText,
            focus: .discountPercent,
            required: false
        )
    }

    private var discountAmountField: some View {
        moneyField(
            title: tr("CatalogIntake_DiscountAmount", "خصم ثابت (ر.ق)"),
            text: $viewModel.discountAmountText,
            focus: .discountAmount,
            required: false
        )
    }

    private func moneyField(
        title: String,
        text: Binding<String>,
        focus: FocusedField,
        required: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(title, required: required)
            TextField("0.00", text: text)
                .font(AdminType.headline)
                .englishNumericInput(text: text, allowsDecimal: true)
                .focused($focusedField, equals: focus)
                .padding(.horizontal, AdminSpacing.md)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(fieldFocusBorder(focusedField == focus))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quantityButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: AdminTouchTarget.expanded, height: AdminTouchTarget.expanded)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus"
            ? tr("CatalogIntake_IncreaseQuantity", "زيادة الكمية")
            : tr("CatalogIntake_DecreaseQuantity", "تقليل الكمية"))
    }

    private var wholesaleCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Toggle(isOn: $viewModel.wholesaleEnabled.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                HStack(spacing: AdminSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .systemTeal).opacity(viewModel.wholesaleEnabled ? 0.18 : 0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal) : AdminSurface.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Wholesale_Selling_Title", "البيع بالجملة (Wholesale)"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(viewModel.wholesaleEnabled
                            ? tr("Wholesale_Active_Hint", "مفعل ومتاح في نقطة البيع للموزعين والعملاء بالجملة")
                            : tr("Wholesale_Inactive_Hint", "غير مفعل (قم بالتشغيل لتحديد سعر الجملة)"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .tint(Color(uiColor: .systemTeal))

            if viewModel.wholesaleEnabled {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    fieldLabel(tr("Wholesale_Price_QAR", "سعر بيع الجملة للوحدة الافتراضية (ر.ق)"), required: true)

                    TextField("0.00", text: $viewModel.wholesalePriceText)
                        .font(PPBrandFont.bold(size: 18))
                        .englishNumericInput(text: $viewModel.wholesalePriceText, allowsDecimal: true)
                        .focused($focusedField, equals: .wholesalePrice)
                        .padding(AdminSpacing.md)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .wholesalePrice))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(viewModel.wholesaleEnabled ? Color(uiColor: .systemTeal).opacity(0.35) : AdminSurface.hairline, lineWidth: 1)
        )
    }

    private var sellingUnitsCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                Label(tr("Selling_Units_Deck_Title", "وحدات ومجموعات البيع"), systemImage: "square.stack.3d.up.fill")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Button {
                    let nextSort = viewModel.quantityGroups.count
                    let newGroup = PPQuantityGroupDraft(
                        id: "pack_\(nextSort + 1)_\(UUID().uuidString.prefix(4))",
                        nameAr: "",
                        nameEn: "",
                        unitsPerGroup: 6,
                        barcode: "",
                        sku: "",
                        sortOrder: nextSort,
                        retailEnabled: true,
                        wholesaleEnabled: viewModel.wholesaleEnabled,
                        retailPriceText: "",
                        wholesalePriceText: "",
                        defaultForRetail: false,
                        defaultForWholesale: false,
                        active: true
                    )
                    viewModel.selectedQuantityGroupForEditing = newGroup
                    viewModel.showQuantityGroupInspector = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(tr("Add_Selling_Unit", "إضافة وحدة"))
                    }
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }

            Text(tr("Selling_Units_Deck_Subtitle", "تحديد أحجام البيع (حبة، شدة، كرتون) مع خصم المخزون التلقائي بالوحدات الأساسية."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                ForEach(viewModel.quantityGroups) { group in
                    sellingUnitRow(for: group)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func sellingUnitRow(for group: PPQuantityGroupDraft) -> some View {
        Button {
            viewModel.selectedQuantityGroupForEditing = group
            viewModel.showQuantityGroupInspector = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(group.defaultForRetail ? AdminSurface.primary.opacity(0.15) : AdminSurface.control)
                        .frame(width: 38, height: 38)
                    Image(systemName: group.unitsPerGroup == 1 ? "cube.fill" : "shippingbox.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(group.defaultForRetail ? AdminSurface.primary : AdminSurface.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.localizedName)
                            .font(AdminType.bodyBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        if group.defaultForRetail {
                            Text(tr("Default_Retail_Badge", "افتراضي للتجزئة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                        if group.defaultForWholesale && group.wholesaleEnabled {
                            Text(tr("Default_Wholesale_Badge", "افتراضي للجملة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(uiColor: .systemTeal))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemTeal).opacity(0.12), in: Capsule())
                        }
                    }
                    Text(group.unitsCountText)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if group.retailEnabled {
                        Text(verbatim: String(format: "%.0f %@", group.retailPrice, tr("QAR", "ر.ق")).normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    if group.wholesaleEnabled {
                        Text(verbatim: String(format: tr("Wholesale_Price_Format", "جملة: %.0f ر.ق"), group.wholesalePrice).normalizedEnglishDigits)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(uiColor: .systemTeal))
                    }
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var releaseScene: some View {
        PPLivePetDecisionSurface(
            eyebrow: tr("CatalogIntake_ReleaseEyebrow", "المراجعة والإتاحة"),
            title: tr("CatalogIntake_ReleaseTitle", "راجع الصنف ثم احفظه في الكتالوج"),
            subtitle: tr("CatalogIntake_ReleaseSubtitle", "اختر الفرع وحالة الظهور. سيُحفظ الصنف عبر مسار الإدارة الحالي من دون تغيير عقد البيانات."),
            symbol: "checkmark.shield.fill"
        ) {
            VStack(spacing: AdminSpacing.sectionSpacing) {
                Button {
                    viewModel.showStorePicker = true
                } label: {
                    HStack(spacing: AdminSpacing.md) {
                        Image(systemName: "storefront.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                            Text(tr("CatalogIntake_OwningStore", "الفرع المالك"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(viewModel.selectedStoreName.isEmpty
                                ? tr("CatalogIntake_SelectStore", "اختر الفرع المالك")
                                : viewModel.selectedStoreName)
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(AdminSpacing.sm)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))

                Toggle(isOn: $viewModel.isDraft) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                        Text(viewModel.isDraft
                            ? tr("CatalogIntake_DraftToggleOn", "حفظ كمسودة غير نشطة")
                            : tr("CatalogIntake_DraftToggleOff", "حفظ كصنف نشط"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(viewModel.isDraft
                            ? tr("CatalogIntake_DraftHint", "لن يظهر الصنف ضمن العناصر النشطة حتى يتم تفعيله.")
                            : tr("CatalogIntake_ActiveHint", "سيصبح الصنف نشطاً بعد نجاح الحفظ."))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .tint(AdminSurface.primary)
                .padding(AdminSpacing.md)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    Text(tr("CatalogIntake_ReviewTitle", "ملخص قبل الحفظ"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    reviewRow(
                        symbol: viewModel.isFood ? "fork.knife" : "shippingbox.fill",
                        title: tr("CatalogIntake_ReviewItem", "الصنف"),
                        value: viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? tr("CatalogIntake_NotSet", "غير محدد")
                            : viewModel.name
                    )
                    if !viewModel.sku.isEmpty {
                        reviewRow(
                            symbol: "barcode",
                            title: tr("CatalogIntake_ReviewSKU", "رمز SKU"),
                            value: viewModel.sku,
                            forceLTR: true
                        )
                    }
                    if !viewModel.barcode.isEmpty {
                        reviewRow(
                            symbol: "barcode.viewfinder",
                            title: tr("CatalogIntake_ReviewBarcode", "الباركود"),
                            value: viewModel.barcode,
                            forceLTR: true
                        )
                    }
                    reviewRow(
                        symbol: "pawprint.fill",
                        title: tr("CatalogIntake_ReviewMainKind", "النوع الرئيسي"),
                        value: viewModel.selectedCategoryDisplayTitle ?? tr("CatalogIntake_NotSet", "غير محدد")
                    )
                    reviewRow(
                        symbol: "tag.fill",
                        title: tr("CatalogIntake_ReviewSubKind", "النوع الفرعي"),
                        value: (viewModel.selectedSubCategoryDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                            ? viewModel.selectedSubCategoryDisplayTitle!
                            : tr("CatalogIntake_NotSet", "غير محدد")
                    )
                    reviewRow(
                        symbol: "circle.on.square.intersection.dotted",
                        title: tr("CatalogIntake_ReviewRetailPrice", "سعر القطاعي"),
                        value: String(format: "%.2f %@", viewModel.calculatedFinalPrice, tr("QAR", "ر.ق")).normalizedEnglishDigits,
                        forceLTR: true
                    )
                    let wholesalePriceValue: Double = {
                        if let defaultW = viewModel.quantityGroups.first(where: { $0.defaultForWholesale && $0.wholesaleEnabled }) ?? viewModel.quantityGroups.first(where: { $0.wholesaleEnabled }), defaultW.wholesalePrice > 0 {
                            return defaultW.wholesalePrice
                        }
                        return Double(viewModel.wholesalePriceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                    }()
                    reviewRow(
                        symbol: "shippingbox.fill",
                        title: tr("CatalogIntake_ReviewWholesalePrice", "سعر الجملة"),
                        value: viewModel.wholesaleEnabled
                            ? (wholesalePriceValue > 0 ? String(format: "%.2f %@", wholesalePriceValue, tr("QAR", "ر.ق")).normalizedEnglishDigits : tr("CatalogIntake_NotSet", "غير محدد"))
                            : tr("CatalogIntake_Disabled", "غير مفعل"),
                        forceLTR: viewModel.wholesaleEnabled && wholesalePriceValue > 0
                    )
                    reviewRow(
                        symbol: "number.square.fill",
                        title: tr("CatalogIntake_ReviewQuantity", "الكمية"),
                        value: viewModel.quantity.englishDigits,
                        forceLTR: true
                    )
                    if viewModel.isFood && viewModel.hasExpiryDate {
                        reviewRow(
                            symbol: "calendar.badge.clock",
                            title: tr("CatalogIntake_ReviewExpiry", "انتهاء الصلاحية"),
                            value: viewModel.expiryDate.formatted(date: .abbreviated, time: .omitted).normalizedEnglishDigits
                        )
                    }
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.14), lineWidth: 1)
                )
            }
        }
    }

    private func reviewRow(
        symbol: String,
        title: String,
        value: String,
        forceLTR: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 24)
            Text(title)
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer(minLength: AdminSpacing.sm)
            Text(verbatim: value.normalizedEnglishDigits)
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, forceLTR ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))
        }
        .accessibilityElement(children: .combine)
    }

    private var catalogActionDock: some View {
        VStack(spacing: AdminSpacing.sm) {
            if let requirement = validationMessage(for: viewModel.activeStage),
               viewModel.activeStage != .governance {
                Label(requirement, systemImage: "circle.dashed")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.sm) {
                        primaryDockButton
                        if viewModel.activeStage.rawValue > 0 { previousDockButton }
                    }
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        if viewModel.activeStage.rawValue > 0 { previousDockButton }
                        primaryDockButton
                    }
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.sm)
        .padding(.bottom, AdminSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(AdminSurface.hairline.opacity(0.65))
        }
    }

    private var previousDockButton: some View {
        Button {
            guard let previous = PPEditorStage(rawValue: viewModel.activeStage.rawValue - 1) else { return }
            move(to: previous)
        } label: {
            Image(systemName: "arrow.backward")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : AdminTouchTarget.expanded)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .accessibilityLabel(tr("CatalogIntake_Previous", "الخطوة السابقة"))
    }

    private var primaryDockButton: some View {
        Button {
            performPrimaryAction()
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else if viewModel.activeStage == .governance {
                    Image(systemName: viewModel.isDraft ? "doc.badge.plus" : "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                }

                Text(primaryActionTitle)
                    .font(AdminType.headline)
                    .lineLimit(2)

                if !viewModel.isSubmitting && viewModel.activeStage != .governance {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
            .padding(.horizontal, AdminSpacing.md)
            .background(
                LinearGradient(
                    colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
            )
            .shadow(color: AdminSurface.primary.opacity(accessibilityReduceMotion ? 0.12 : 0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.isSubmitting)
        .accessibilityHint(primaryActionHint)
    }

    private var primaryActionTitle: String {
        if viewModel.activeStage != .governance {
            return tr("CatalogIntake_Continue", "متابعة")
        }
        if viewModel.editingAccessory != nil {
            return tr("CatalogIntake_SaveChanges", "حفظ التغييرات")
        }
        return viewModel.isDraft
            ? tr("CatalogIntake_CreateDraft", "إنشاء المسودة")
            : tr("CatalogIntake_SaveActive", "حفظ واعتماد الصنف")
    }

    private var primaryActionHint: String {
        if viewModel.activeStage == .governance {
            return tr("CatalogIntake_SubmitHint", "يتحقق من البيانات ثم يحفظ الصنف عبر مسار الإدارة الحالي")
        }
        return tr("CatalogIntake_ContinueHint", "يتحقق من هذه الخطوة ثم ينتقل إلى التالية")
    }

    private func performPrimaryAction() {
        focusedField = nil
        if viewModel.activeStage == .governance {
            guard let issue = firstIncompleteStage else {
                stageMessage = nil
                viewModel.saveAccessory()
                return
            }
            stageMessage = issue.message
            move(to: issue.stage, preservingMessage: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(notification: .announcement, argument: issue.message)
            return
        }

        if let message = validationMessage(for: viewModel.activeStage) {
            stageMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(notification: .announcement, argument: message)
            return
        }

        guard let next = PPEditorStage(rawValue: viewModel.activeStage.rawValue + 1) else { return }
        stageMessage = nil
        move(to: next)
    }

    private var catalogSubmissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()
            VStack(spacing: AdminSpacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AdminSurface.primary)
                Text(tr("CatalogIntake_Submitting", "جارٍ حفظ الصنف بأمان"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(tr("CatalogIntake_SubmittingSub", "قد تُرفع الصور أولاً ثم يُحفظ سجل الكتالوج. لا تغلق التطبيق."))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AdminSpacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("CatalogIntake_Submitting", "جارٍ حفظ الصنف بأمان"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilitySortPriority(100)
    }

    // MARK: - iPhone App-Switcher Multitasking Steps Deck

    private var catalogStepsAppSwitcherOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed translucent frosted backdrop with tap-to-dismiss
                Color.black.opacity(0.40)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            showStepsAppSwitcher = false
                        }
                    }

                VStack(spacing: 0) {
                    // Top App Switcher Bar
                    appSwitcherTopBar

                    // 3D Horizontal Multi-Tasker Cards Carousel
                    appSwitcherCarousel(in: geo)

                    // Bottom Quick Dismiss Indicator / Instruction
                    appSwitcherBottomHint
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("CatalogIntake_StepsSwitcherTitle", "مراحل إضافة الصنف"))
    }

    private var appSwitcherTopBar: some View {
        HStack(spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: viewModel.isFood ? "fork.knife" : "shippingbox.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 34, height: 34)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("CatalogIntake_StepsSwitcherTitle", "مراحل إضافة الصنف"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(format: tr("CatalogIntake_CompletedFormat", "%ld من 4 مكتملة"), completedStageCount))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer(minLength: AdminSpacing.xs)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    showStepsAppSwitcher = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .accessibilityLabel(tr("Close", "إغلاق"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.md)
        .padding(.bottom, AdminSpacing.xs)
    }

    private func appSwitcherCarousel(in geo: GeometryProxy) -> some View {
        let cardWidth = min(geo.size.width * 0.78, 320.0)
        let cardHeight = min(geo.size.height * 0.62, 530.0)
        let horizontalPadding = max(24.0, (geo.size.width - cardWidth) / 2.0)

        return ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(PPEditorStage.allCases) { stage in
                        GeometryReader { cardGeo in
                            let frame = cardGeo.frame(in: .named("AppSwitcherDeckSpace"))
                            let center = geo.size.width / 2.0
                            let distance = frame.midX - center
                            let normalized = distance / (cardWidth + 18.0)
                            let scale = accessibilityReduceMotion ? 1.0 : max(0.86, 1.0 - abs(normalized) * 0.12)
                            let opacity = accessibilityReduceMotion ? 1.0 : max(0.70, 1.0 - abs(normalized) * 0.28)
                            let rotationY = accessibilityReduceMotion ? 0.0 : Double(-normalized * 12.0)

                            appSwitcherCard(for: stage, width: cardWidth, height: cardHeight)
                                .scaleEffect(scale)
                                .opacity(opacity)
                                .rotation3DEffect(
                                    .degrees(rotationY),
                                    axis: (x: 0.0, y: 1.0, z: 0.0),
                                    perspective: 0.55
                                )
                                .shadow(
                                    color: Color.black.opacity(stage == viewModel.activeStage ? 0.26 : 0.12),
                                    radius: stage == viewModel.activeStage ? 22 : 12,
                                    x: 0,
                                    y: stage == viewModel.activeStage ? 12 : 6
                                )
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .id(stage)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
            .coordinateSpace(name: "AppSwitcherDeckSpace")
            .onAppear {
                scrollProxy.scrollTo(viewModel.activeStage, anchor: .center)
            }
        }
        .frame(height: cardHeight + 36)
    }

    private func appSwitcherCard(for stage: PPEditorStage, width: CGFloat, height: CGFloat) -> some View {
        let isCurrent = stage == viewModel.activeStage
        let isDone = validationMessage(for: stage) == nil

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            move(to: stage)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                showStepsAppSwitcher = false
            }
        } label: {
            VStack(spacing: 0) {
                // Card Header (App Icon + Step Name + Status Pill)
                appSwitcherCardHeader(stage: stage, isCurrent: isCurrent, isDone: isDone)

                // Simulated App Window Content
                appSwitcherCardBody(stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AdminSurface.surface)

                // Card Footer / Jump Action
                appSwitcherCardFooter(stage: stage, isCurrent: isCurrent)
            }
            .frame(width: width, height: height)
            .background(AdminSurface.card)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        isCurrent
                            ? AdminSurface.primary
                            : (isDone ? Color(uiColor: .ppSuccess).opacity(0.4) : AdminSurface.hairline),
                        lineWidth: isCurrent ? 2.0 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stageEyebrow(stage)): \(stageTitle(stage))")
        .accessibilityHint(tr("CatalogIntake_AppSwitcherCardHint", "اضغط للانتقال إلى هذه الخطوة وتكبيرها"))
    }

    private func appSwitcherCardHeader(stage: PPEditorStage, isCurrent: Bool, isDone: Bool) -> some View {
        HStack(spacing: AdminSpacing.xs) {
            stageIconSquircle(stage: stage)

            VStack(alignment: .leading, spacing: 2) {
                Text(stageEyebrow(stage))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(shortStageTitle(stage))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isCurrent {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AdminSurface.primary)
                        .frame(width: 6, height: 6)
                    Text(tr("CatalogIntake_ActiveNowPill", "قيد التعديل"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            } else if isDone {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(tr("CatalogIntake_DonePill", "مكتملة"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(Color(uiColor: .ppSuccess))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 9, weight: .bold))
                    Text(tr("CatalogIntake_NeedsInputPill", "بحاجة لبيانات"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(Color(uiColor: .ppWarning))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, AdminSpacing.sm)
        .background(AdminSurface.surface.opacity(0.95))
    }

    private func stageIconSquircle(stage: PPEditorStage) -> some View {
        let (symbol, gradientColors): (String, [Color]) = {
            switch stage {
            case .identity:
                return ("photo.stack.fill", [Color.pink, AdminSurface.primary])
            case .bioVault:
                return ("slider.horizontal.3", [Color.orange, Color.yellow])
            case .pricing:
                return ("tag.fill", [Color(uiColor: .ppSuccess), Color.teal])
            case .governance:
                return ("shield.checkerboard", [Color.blue, Color.purple])
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 28, height: 28)
        .shadow(color: gradientColors[0].opacity(0.3), radius: 4, y: 2)
    }

    @ViewBuilder
    private func appSwitcherCardBody(stage: PPEditorStage) -> some View {
        switch stage {
        case .identity:
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                if !viewModel.existingImageURLs.isEmpty || !viewModel.pickedImages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(viewModel.existingImageURLs.prefix(3).enumerated()), id: \.offset) { _, url in
                            AdminRemoteImage(url: URL(string: url), contentMode: .fill, targetSize: CGSize(width: 48, height: 48)) {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        ForEach(Array(viewModel.pickedImages.prefix(3).enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if viewModel.totalImageCount > 3 {
                            Text("+\(viewModel.totalImageCount - 3)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .frame(width: 48, height: 48)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(AdminSurface.primary)
                        Text(tr("CatalogIntake_NoPhotosYet", "لا توجد صور مضافة بعد"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(AdminSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_NameLabel", "اسم الصنف"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(viewModel.name.isEmpty ? tr("CatalogIntake_NameMissing", "لم يدخل الاسم بالعربي") : viewModel.name)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(viewModel.name.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                        .lineLimit(1)
                    if !viewModel.nameEn.isEmpty {
                        Text(viewModel.nameEn)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                if !viewModel.desc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("CatalogIntake_DescriptionLabel", "الوصف"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(viewModel.desc)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AdminSpacing.md)

        case .bioVault:
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_CategoryLabel", "الفئة الرئيسية"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.primary)
                        Text(viewModel.selectedMainKind?.kindName ?? tr("CatalogIntake_CategoryMissing", "غير محددة"))
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(viewModel.selectedMainKind == nil ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_SubcategoryLabel", "الفئات الفرعية"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    let subText: String = {
                        if viewModel.isAllSubCategoriesSelected {
                            return tr("CatalogIntake_AllSubcategoriesPrompt", "جميع السلالات والتفريعات")
                        } else if viewModel.selectedSubKinds.count > 0 {
                            return String(format: tr("CatalogIntake_SubkindsCountFormat", "%ld فئات فرعية"), viewModel.selectedSubKinds.count)
                        } else if let sub = viewModel.selectedSubKind {
                            return sub.subKindName
                        } else {
                            return tr("CatalogIntake_NoSubcategorySelected", "لم يتم التحديد")
                        }
                    }()
                    Text(subText)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_WeightLabel", "الوزن أو الحجم"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(viewModel.weightText.isEmpty ? tr("CatalogIntake_WeightUnspecified", "غير محدد") : "\(viewModel.weightText) \(viewModel.weightUnit)")
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AdminSpacing.md)

        case .pricing:
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_PriceLabel", "سعر البيع للجمهور"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(viewModel.priceText.isEmpty ? "0" : viewModel.priceText)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Rials", alter: "ر.ق"))
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                if !viewModel.costPriceText.isEmpty {
                    HStack(spacing: 6) {
                        Text(tr("CatalogIntake_CostLabel", "التكلفة:"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text("\(viewModel.costPriceText) \(Language.get("Rials", alter: "ر.ق"))")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                    Text(String(format: tr("CatalogIntake_QuantityFormat", "الكمية المتاحة: %ld قطعة"), viewModel.quantity))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(AdminSpacing.md)

        case .governance:
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("CatalogIntake_BranchLabel", "الفرع المالك"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.primary)
                        Text(viewModel.selectedStoreName.isEmpty ? tr("CatalogIntake_StoreMissing", "لم يتم اختيار الفرع") : viewModel.selectedStoreName)
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(viewModel.selectedStoreName.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                    Text(viewModel.isDraft ? tr("CatalogIntake_DraftState", "مسودة غير ظاهرة") : tr("CatalogIntake_ActiveState", "جاهز للإتاحة في المتجر"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("CatalogIntake_ChecklistLabel", "مؤشرات الجاهزية:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(spacing: 4) {
                        checklistDot(label: tr("CatalogIntake_ShortIdentity", "الهوية"), done: validationMessage(for: .identity) == nil)
                        checklistDot(label: tr("CatalogIntake_ShortSpecs", "المواصفات"), done: validationMessage(for: .bioVault) == nil)
                        checklistDot(label: tr("CatalogIntake_ShortPricing", "التسعير"), done: validationMessage(for: .pricing) == nil)
                        checklistDot(label: tr("CatalogIntake_ShortRelease", "الإتاحة"), done: validationMessage(for: .governance) == nil)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AdminSpacing.md)
        }
    }

    private func checklistDot(label: String, done: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(done ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(done ? AdminSurface.primaryText : AdminSurface.secondaryText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(done ? Color(uiColor: .ppSuccess).opacity(0.10) : AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func appSwitcherCardFooter(stage: PPEditorStage, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(tr("CatalogIntake_CurrentActiveStage", "أنت في هذه الخطوة الآن"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            } else {
                Text(tr("CatalogIntake_SwitchToStage", "اضغط للانتقال الفوري"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            isCurrent ? AdminSurface.primary.opacity(0.08) : AdminSurface.control.opacity(0.8),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, AdminSpacing.sm)
    }

    private var appSwitcherBottomHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 12))
            Text(tr("CatalogIntake_AppSwitcherSwipeHint", "اسحب أفقياً لتصفح الخطوات، أو اضغط على أي بطاقة لتكبيرها"))
                .font(AdminType.caption2)
        }
        .foregroundStyle(AdminSurface.secondaryText.opacity(0.9))
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, AdminSpacing.xs)
        .background(AdminSurface.surface.opacity(0.65), in: Capsule())
        .padding(.bottom, AdminSpacing.sm)
    }

    private var completedStageCount: Int {
        PPEditorStage.allCases.filter { validationMessage(for: $0) == nil }.count
    }

    private var firstIncompleteStage: (stage: PPEditorStage, message: String)? {
        for stage in PPEditorStage.allCases {
            if let message = validationMessage(for: stage) {
                return (stage, message)
            }
        }
        return nil
    }

    private func validationMessage(for stage: PPEditorStage) -> String? {
        switch stage {
        case .identity:
            if viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return tr("CatalogIntake_ValidationName", "أدخل اسم الصنف أولاً.")
            }
            let trimmedNameEn = viewModel.nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNameEn.isEmpty && trimmedNameEn.utf16.count > 90 {
                return tr("CatalogIntake_ValidationNameLengthEn", "يجب ألا يتجاوز الاسم بالإنجليزية 90 حرفاً.")
            }
        case .bioVault:
            if viewModel.selectedMainKind == nil {
                return tr("CatalogIntake_ValidationCategory", "اختر الفئة الرئيسية للصنف.")
            }
            if !viewModel.isValidWeightInput() {
                return tr("CatalogIntake_ValidationWeight", "أدخل وزناً أو حجماً صالحاً وبحد أقصى ثلاث منازل عشرية.")
            }
        case .pricing:
            let clean = viewModel.priceText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(clean), value.isFinite, value > 0 {
                // Continue to optional discount validation.
            } else {
                return tr("CatalogIntake_ValidationPrice", "أدخل سعراً أساسياً صحيحاً أكبر من صفر.")
            }
            if !viewModel.isValidDiscountPercentInput() {
                return tr("CatalogIntake_ValidationDiscountPercent", "أدخل نسبة خصم بين 0 و100 وبحد أقصى منزلتين عشريتين.")
            }
            if !viewModel.isValidDiscountAmountInput() {
                return tr("CatalogIntake_ValidationDiscountAmount", "أدخل مبلغ خصم صالحاً وبحد أقصى منزلتين عشريتين.")
            }
        case .governance:
            if viewModel.selectedStoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return tr("CatalogIntake_ValidationStore", "اختر الفرع المالك للصنف.")
            }
        }
        return nil
    }

    private func move(to stage: PPEditorStage, preservingMessage: Bool = false) {
        focusedField = nil
        if !preservingMessage { stageMessage = nil }
        UISelectionFeedbackGenerator().selectionChanged()
        if accessibilityReduceMotion {
            viewModel.activeStage = stage
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                viewModel.activeStage = stage
            }
        }
    }

    private func progressColor(for stage: PPEditorStage) -> Color {
        if stage == viewModel.activeStage { return AdminSurface.primary }
        return validationMessage(for: stage) == nil
            ? Color(uiColor: .ppSuccess)
            : AdminSurface.secondaryText
    }

    private var catalogScreenTitle: String {
        if viewModel.editingAccessory != nil {
            return viewModel.isFood
                ? tr("CatalogIntake_EditFoodTitle", "تعديل غذاء أو مكمل")
                : tr("CatalogIntake_EditAccessoryTitle", "تعديل ملحق")
        }
        return viewModel.isFood
            ? tr("CatalogIntake_AddFoodTitle", "إضافة غذاء أو مكمل")
            : tr("CatalogIntake_AddAccessoryTitle", "إضافة ملحق")
    }

    private func stageEyebrow(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_StageOne", "الخطوة 1")
        case .bioVault: return tr("CatalogIntake_StageTwo", "الخطوة 2")
        case .pricing: return tr("CatalogIntake_StageThree", "الخطوة 3")
        case .governance: return tr("CatalogIntake_StageFour", "الخطوة 4")
        }
    }

    private func shortStageTitle(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_ShortIdentity", "الهوية")
        case .bioVault: return tr("CatalogIntake_ShortSpecs", "المواصفات")
        case .pricing: return tr("CatalogIntake_ShortPricing", "التسعير")
        case .governance: return tr("CatalogIntake_ShortRelease", "الإتاحة")
        }
    }

    private func stageTitle(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_StageIdentity", "الهوية والوسائط")
        case .bioVault: return tr("CatalogIntake_StageSpecs", "التصنيف والمواصفات")
        case .pricing: return tr("CatalogIntake_StagePricing", "السعر والمخزون")
        case .governance: return tr("CatalogIntake_StageRelease", "المراجعة والإتاحة")
        }
    }

    private func stageQuestion(_ stage: PPEditorStage) -> String {
        switch stage {
        case .identity: return tr("CatalogIntake_QuestionIdentity", "كيف سيجد الفريق والعملاء هذا الصنف؟")
        case .bioVault: return tr("CatalogIntake_QuestionSpecs", "ما فئته ومواصفاته التشغيلية؟")
        case .pricing: return tr("CatalogIntake_QuestionPricing", "ما السعر والخصم والكمية المتاحة؟")
        case .governance: return tr("CatalogIntake_QuestionRelease", "أين سيُحفظ، وهل سيكون نشطاً؟")
        }
    }

    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.secondaryText)
            if required {
                Text("*")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(uiColor: .ppError))
                    .accessibilityHidden(true)
            }
        }
    }

    private func fieldFocusBorder(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
            .strokeBorder(focused ? AdminSurface.primary : AdminSurface.hairline, lineWidth: focused ? 1.5 : 0.75)
    }

    private func scrollToFocusedField(proxy: ScrollViewProxy, targetField: FocusedField? = nil) {
        let field = targetField ?? focusedField
        guard let field = field else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(field, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.20)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
    }

    private func showCatalogDiscardAlert() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: tr("Discard_Changes_Title", "تنبيه"),
            subtitle: tr("Discard_Changes_Message", "ستفقد التعديلات غير المحفوظة إذا غادرت الآن."),
            confirmButton: tr("Discard_Changes_Confirm", "مغادرة وتجاهل"),
            cancelButton: tr("Cancel", "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.discardChangesAndDismiss()
            },
            cancelBlock: nil
        )
    }

    private func tr(_ key: String, _ fallback: String) -> String {
        Language.get(key, alter: fallback)
    }
}

// MARK: - Scroll Dismisses Keyboard Compatibility

fileprivate extension View {
    @ViewBuilder
    func scrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
