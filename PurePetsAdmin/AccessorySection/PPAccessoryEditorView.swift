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
    var acceptedProductID: String?
    var successMessage: String
    let oldImageURLs: [String]
}

/// Prepared, command-bound media for exactly one draft animal.
///
/// Bytes are normalized before hashing so retries keep one immutable Storage
/// object path. The remote URL is retained only after Storage confirms it; it is
/// then serialized into the existing live-unit `mediaURLs` contract.
private struct PPLivePetUnitPhotoDraft {
    let image: UIImage
    let encodedData: Data
    let contentSHA256: String
    var objectWasUploaded: Bool
    var uploadedURL: String?
}

private struct PPLivePetUnitPhotoMetadataSnapshot: Sendable {
    let contentType: String?
    let size: Int64
    let customMetadata: [String: String]
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
    @Published var desc: String = "" { didSet { updateUnsavedChanges() } }
    
    // Species & Breed
    @Published var selectedMainKind: MainKindsModel? = nil {
        didSet {
            if oldValue?.id != selectedMainKind?.id {
                selectedSubKind = nil
            }
            updateUnsavedChanges()
        }
    }
    @Published var selectedSubKind: SubKindModel? = nil { didSet { updateUnsavedChanges() } }
    
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

    // Pricing
    @Published var priceText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var discountPercentText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var discountAmountText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var costPriceText: String = "" { didSet { updateUnsavedChanges() } }
    
    // Inventory, SKU & Stock
    @Published var sku: String = "" { didSet { updateUnsavedChanges() } }
    @Published var barcode: String = "" { didSet { updateUnsavedChanges() } }
    @Published var quantity: Int = 1 { didSet { updateUnsavedChanges() } }
    @Published var condition: AccessConditions = .new { didSet { updateUnsavedChanges() } }
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
            return
        }

        name = acc.name ?? ""
        desc = acc.desc ?? ""
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

        hydrateWeight(from: acc)

        selectedStoreID = (acc.storeID ?? "").isEmpty == false ? acc.storeID! : "main_store"
        selectedStoreName = (acc.storeName ?? "").isEmpty == false ? acc.storeName! : Language.get("Main Store", alter: "المتجر الرئيسي")
        
        isDraft = !acc.active
        existingImageURLs = acc.imageURLsArray ?? []
        existingImageMetadata = alignedImageMetadata(
            urls: existingImageURLs,
            metadata: acc.imageMeta ?? []
        )
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

    func loadMainKinds() {
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            self.matchSelectedCategories()
            self.finishInitialHydration()
            return
        }

        isLoadingKinds = true
        kindsErrorMessage = nil

        AppManager.shared().fetchMainKinds { [weak self] kinds, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingKinds = false
                if let err = error {
                    self.kindsErrorMessage = err.localizedDescription
                } else if let list = kinds as? [MainKindsModel], !list.isEmpty {
                    self.availableMainKinds = list
                    self.matchSelectedCategories()
                } else {
                    self.kindsErrorMessage = Language.get("Something went wrong.", alter: "تعذر تحميل قائمة الأنواع")
                }
                self.finishInitialHydration()
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
        if acc.petMainCategoryID > 0 {
            if let matchedMain = availableMainKinds.first(where: { $0.id == acc.petMainCategoryID }) {
                self.selectedMainKind = matchedMain
                if acc.petSubCategoryID > 0, let subList = matchedMain.subKindsArray as? [SubKindModel] {
                    self.selectedSubKind = subList.first(where: { $0.id == acc.petSubCategoryID })
                }
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
        PPStaffAuth.shared().cachedCurrentStaff?.hasPermission("stock.cost.view") ?? false
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
            supplier: liveSupplier
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
            notes: unit.notes
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
        return (selectedMainKind?.subKindsArray as? [SubKindModel]) ?? []
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
        return String(format: "%.2f–%.2f %@", minimum, maximum, currencySymbol)
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
            return String(format: "%.0f %@", value, currencySymbol)
        }
        return String(format: "%.2f %@", value, currencySymbol)
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
    }

    // MARK: - Validation

    func validate() -> (isValid: Bool, message: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || basePrice <= 0 {
            return (false, Language.get("Name and price are required.", alter: "يرجى إدخال اسم وسعر المنتج بدقة."))
        }
        if selectedMainKind == nil {
            return (false, Language.get("Please select pet species.", alter: "يرجى اختيار النوع والفئة الرئيسية للحيوان."))
        }
        if !isValidWeightInput() {
            return (false, Language.get(
                "CatalogIntake_ValidationWeight",
                alter: "أدخل وزناً أو حجماً صالحاً وبحد أقصى ثلاث منازل عشرية."
            ))
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
            if desc.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 4_000 {
                return (false, Language.get("LivePetIntake_ValidationDescriptionLength", alter: "يجب ألا يتجاوز الوصف 4000 حرف."))
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
        accessory.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
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
        accessory.quantity = max(0, quantity)
        accessory.noStock = (quantity <= 0)
        
        accessory.condition = (isFood || condition == .new) ? .new : .used
        accessory.isNew = (accessory.condition != .used)
        accessory.accessKindType = selectedKind
        
        accessory.petMainCategoryID = selectedMainKind?.id ?? 0
        accessory.petSubCategoryID = selectedSubKind?.id ?? 0
        
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

    private func finalizeAccessorySave(accessory: PetAccessory, oldImageURLs: [String]) {
        if isLivePet {
            Task { @MainActor [weak self] in
                await self?.finalizeLivePetSave(accessory: accessory, oldImageURLs: oldImageURLs)
            }
            return
        }
        AccessoryManager.shared().createOrUpdate(accessory) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let err = error {
                    self.isSubmitting = false
                    self.errorMessage = err.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                self.commitSavedAccessory(accessory)

                if let branchId = accessory.branchID, !branchId.isEmpty, accessory.quantity > 0 {
                    PPBranchInventoryService.shared.adjustStock(
                        productId: accessory.accessoryID ?? "",
                        branchId: branchId,
                        newQuantity: accessory.quantity,
                        type: "purchase",
                        referenceId: "catalog_init",
                        reason: "catalog_product_init",
                        notes: "Initialized during product catalog creation"
                    ) { _ in }
                }

                // Clean up removed old images from Storage (best-effort)
                let newSet = Set(accessory.imageURLsArray ?? [])
                for oldURL in oldImageURLs {
                    if !oldURL.isEmpty && !newSet.contains(oldURL) {
                        if let ref = try? Storage.storage().reference(forURL: oldURL) {
                            ref.delete { _ in }
                        }
                    }
                }

                let message = (self.editingAccessory != nil)
                    ? Language.get("Your changes were saved successfully.", alter: "تم حفظ التعديلات بنجاح")
                    : Language.get("Accessory has been created.", alter: "تمت إضافة الصنف بنجاح")
                self.completeSuccessfulSave(message: message)
            }
        }
    }

    private func commitSavedAccessory(_ saved: PetAccessory) {
        guard let original = editingAccessory else { return }
        original.accessoryID = saved.accessoryID
        original.name = saved.name
        original.desc = saved.desc
        original.sku = saved.sku
        original.barcode = saved.barcode
        original.costPrice = saved.costPrice
        original.price = saved.price
        original.discountPercent = saved.discountPercent
        original.discountAmount = saved.discountAmount
        original.weightText = saved.weightText
        original.weight = saved.weight
        original.weightUnit = saved.weightUnit
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
    }

    private func commitConfirmedLivePetForm(retainedURLs: [String]) {
        guard let original = editingAccessory else { return }
        original.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        original.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let productID = editingAccessory?.accessoryID ?? ""
        let actorUID = Auth.auth().currentUser?.uid ?? ""
        var catalogValues: [String: Any] = [
            "name": accessory.name ?? "",
            "desc": accessory.desc ?? "",
            "ownerID": accessory.ownerID,
            "storeID": accessory.storeID ?? "",
            "storeName": accessory.storeName ?? "",
            "petMainCategoryID": accessory.petMainCategoryID,
            "petSubCategoryID": accessory.petSubCategoryID,
            "accessKindType": 3,
            "product_type": "live",
            "category": "Live Pets",
            "imageURLsArray": accessory.imageURLsArray ?? [],
            "active": accessory.active,
            "showInAppMarket": !isDraft,
            "isNew": true,
            "updatedBy": actorUID,
        ]
        if liveInventoryMode == .quantity {
            catalogValues["discountPercent"] = accessory.discountPercent ?? NSNull()
            catalogValues["discountAmount"] = accessory.discountAmount ?? NSNull()
            catalogValues["hasOffer"] = accessory.hasOffer
        }

        let unitPayloads: [[String: Any]] = livePetUnits.map { unit in
            let sellingPrice = Double(unit.sellingPriceText.replacingOccurrences(of: ",", with: ".")) ?? basePrice
            let purchaseCost = Double(unit.purchaseCostText.replacingOccurrences(of: ",", with: "."))
            return [
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
                "desc": accessory.desc ?? "",
                "ownerID": accessory.ownerID,
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
                "imageURLsArray": accessory.imageURLsArray ?? [],
                "isNew": true,
                "hasOffer": liveInventoryMode == .individual ? false : accessory.hasOffer,
                "showInAppMarket": !isDraft,
                "product_type": "live",
                "category": "Live Pets",
                "inventoryMode": liveInventoryMode.rawValue,
                "costPrice": liveInventoryMode == .quantity ? groupCost : 0,
                "supplier": liveSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "arrivalDate": ISO8601DateFormatter().string(from: liveArrivalDate),
                "notes": liveIntakeNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                "reorderLevel": 5,
                "units": liveInventoryMode == .individual ? unitPayloads : [],
            ]
            if liveInventoryMode == .individual {
                mutationPayload["standardSellingPrice"] = basePrice
            }
        } else if liveInventoryMode == .individual {
            action = "update_standard_selling_price"
            mutationProductID = productID
            mutationCommandID = PPLivePetInventoryService.commandID("standard-selling-price")
            mutationPayload = ["standardSellingPrice": basePrice]
        } else {
            action = "update"
            mutationProductID = productID
            mutationCommandID = nil
            mutationPayload = [
                "quantity": max(0, quantity),
                "price": basePrice,
                "finalPrice": calculatedFinalPrice,
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
            acceptedProductID: nil,
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
                try persistLivePetRecovery(recovery)
            }

            guard let acceptedProductID = recovery.acceptedProductID, !acceptedProductID.isEmpty else {
                throw PPLivePetServiceError.invalidResponse
            }
            var catalogValues = try dictionary(from: recovery.catalogValuesData)
            catalogValues["updatedAt"] = FieldValue.serverTimestamp()
            try await PPLivePetInventoryService.updateCatalogPresentation(
                productID: acceptedProductID,
                values: catalogValues
            )

            let retainedURLs = catalogValues["imageURLsArray"] as? [String] ?? []
            let confirmedSuccessMessage = recovery.successMessage
            clearLivePetRecovery()
            cleanupRemovedImages(oldImageURLs: recovery.oldImageURLs, retainedURLs: retainedURLs)
            if let confirmedDraft = pendingSavedAccessoryDraft {
                commitSavedAccessory(confirmedDraft)
            } else {
                commitConfirmedLivePetForm(retainedURLs: retainedURLs)
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

// MARK: - Reimagined Flagship Screen

struct PPAccessoryEditorScreen: View {
    @StateObject var viewModel: PPAccessoryEditorViewModel
    @FocusState private var focusedField: FormField?
    @Namespace private var stageAnimation
    @State private var showQuantityAlert: Bool = false
    @State private var quantityAlertText: String = ""
    
    enum FormField: Hashable {
        case name, desc, price, discountPercent, discountAmount, quantity, passport, weight
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
                viewModel.showStorePicker = false
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .alert(Language.get("EditQuantity", alter: "تعديل الكمية"), isPresented: $showQuantityAlert) {
            TextField(Language.get("Quantity", alter: "الكمية"), text: $quantityAlertText)
                .englishNumericInput(text: $quantityAlertText, allowsDecimal: false)
            Button(Language.get("Save", alter: "حفظ")) {
                if let val = Int(quantityAlertText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    viewModel.quantity = max(0, val)
                }
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
        } message: {
            Text(Language.get("EnterQuantityPrompt", alter: "أدخل كمية المخزون المتاحة لهذا الصنف"))
        }
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
                HStack(spacing: 8) {
                    // Active Live Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(viewModel.isDraft ? Language.get("Draft", alter: "مسودة") : Language.get("Active", alter: "نشط"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 38)
                    .background(
                        (viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                    // Primary Save Pill
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark",
                        isLoading: viewModel.isSubmitting
                    ) {
                        viewModel.saveAccessory()
                    }
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
                        Text("\(viewModel.totalImageCount)")
                            .font(.system(size: 10, weight: .bold))
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
                    Text(viewModel.selectedMainKind?.kindName ?? Language.get("General", alter: "عام"))
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
                    Text(viewModel.formattedFinalPrice)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primary)
                        .monospacedDigit()

                    if viewModel.calculatedFinalPrice < viewModel.basePrice && viewModel.basePrice > 0 {
                        Text(String(format: "%.0f %@", viewModel.basePrice, Language.get("QAR", alter: "ر.ق")))
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
                Text(viewModel.isIndividualLivePet ? (viewModel.livePetUnits.first?.ringTag.isEmpty == false ? viewModel.livePetUnits.first!.ringTag : "RING-TAG") : "BATCH-SKU")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                    Text(viewModel.isIndividualLivePet ? "\(viewModel.livePetUnits.count) سجل فردي" : "كمية: \(viewModel.quantity)")
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
                    Text(viewModel.formattedFinalPrice)
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
                Text("\(viewModel.totalImageCount)/9 " + Language.get("Photos", alter: "صور"))
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

            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("ItemName", alter: "اسم الصنف أو الحيوان"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                TextField(Language.get("EnterItemName", alter: "أدخل اسم المنتج بدقة..."), text: $viewModel.name)
                    .font(AdminType.callout)
                    .focused($focusedField, equals: .name)
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focusedField == .name ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Description", alter: "الوصف التفصيلي والمواصفات"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                TextEditor(text: $viewModel.desc)
                    .font(AdminType.callout)
                    .focused($focusedField, equals: .desc)
                    .frame(minHeight: 88)
                    .padding(8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focusedField == .desc ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
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
                            Text(viewModel.selectedMainKind?.kindName ?? Language.get("SelectSpecies", alter: "اختر النوع..."))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(viewModel.selectedMainKind != nil ? AdminSurface.primaryText : AdminCommandInk.tertiary)
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
                Text("\(viewModel.livePetUnits.count)/100 " + Language.get("Units", alter: "حيوان"))
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
                    Text("#\(index + 1)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
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

                TextField("QA-RING-000", text: binding.ringTag)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .environment(\.layoutDirection, .leftToRight)
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
        VStack(alignment: .leading, spacing: 14) {
            Label(Language.get("ProductSpecs", alter: "المواصفات وحالة العنصر"), systemImage: "slider.horizontal.3")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            if !viewModel.isFood {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Condition", alter: "حالة المنتج"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    Picker(Language.get("Condition", alter: "الحالة"), selection: $viewModel.condition) {
                        Text(Language.get("Condition_New", alter: "جديد تماماً")).tag(AccessConditions.new)
                        Text(Language.get("Condition_Used", alter: "مستعمل بحالة جيدة")).tag(AccessConditions.used)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Weight specifications
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Weight", alter: "الوزن أو الحجم"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    TextField("0.0", text: $viewModel.weightText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .englishNumericInput(text: $viewModel.weightText, allowsDecimal: true)
                        .focused($focusedField, equals: .weight)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Unit", alter: "الوحدة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Picker("", selection: $viewModel.weightUnit) {
                        Text("kg").tag("kg")
                        Text("g").tag("g")
                        Text("L").tag("L")
                        Text("ml").tag("ml")
                    }
                    .pickerStyle(.segmented)
                    .frame(height: 44)
                }
            }

            // Expiry Date (if food)
            if viewModel.isFood {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $viewModel.hasExpiryDate) {
                        Label(Language.get("HasExpiryDate", alter: "تاريخ انتهاء الصلاحية"), systemImage: "calendar.badge.clock")
                            .font(AdminType.calloutBold)
                    }
                    .tint(AdminSurface.primary)

                    if viewModel.hasExpiryDate {
                        DatePicker("", selection: $viewModel.expiryDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding(.top, 4)
                    }
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

    // MARK: - 7. STAGE 3: Pricing & Profit Engine Canvas

    private var pricingStageCanvas: some View {
        VStack(spacing: 16) {
            // Financial Pricing Deck
            financialPricingDeck

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
                    Text(
                        viewModel.isIndividualLivePet
                            ? Language.get("LivePet_Standard_SellingPrice_QAR", alter: "السعر القياسي (ر.ق)")
                            : Language.get("BasePrice", alter: "السعر الأساسي (ر.ق)")
                    )
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                    TextField("0.00", text: $viewModel.priceText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .englishNumericInput(text: $viewModel.priceText, allowsDecimal: true)
                        .focused($focusedField, equals: .price)
                        .padding(14)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !viewModel.isIndividualLivePet {
                    // Discount Percent
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("DiscountPercent", alter: "نسبة الخصم (%)"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)

                        TextField("0", text: $viewModel.discountPercentText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
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

            // Customer Final Price Plate
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("FinalCustomerPrice", alter: "السعر النهائي في التطبيق للعميل"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(viewModel.formattedFinalPrice)
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primary)
                }
                Spacer()
                if viewModel.calculatedFinalPrice < viewModel.basePrice && viewModel.basePrice > 0 {
                    Text(String(format: Language.get("DiscountSavings", alter: "خصم %.0f ر.ق"), viewModel.basePrice - viewModel.calculatedFinalPrice))
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
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
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
                    Text(String(format: "%.1f%%", margin))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                    Text(String(format: "+%.0f %@", profit, Language.get("QAR", alter: "ر.ق")))
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

                Text("\(viewModel.quantity)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        quantityAlertText = "\(viewModel.quantity)"
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                        dismiss()
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
                                                    Text("\(subKindsCount) " + Language.get("BreedsAvailable", alter: "سلالة مسجلة"))
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
                                        dismiss()
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
private struct PPAccessoryEditorExperienceRouter: View {
    @ObservedObject var viewModel: PPAccessoryEditorViewModel

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
    @Namespace private var genderSelectionNamespace

    private enum FocusedField: Hashable {
        case name
        case description
        case standardPrice
        case discountPercent
        case discountAmount
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
                    .padding(.bottom, AdminSpacing.lg)
                }
            }
            .scrollDismissesKeyboardCompat()
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
                onSelect: { selectedID in
                    viewModel.selectedMainKind = viewModel.availableMainKinds.first { String($0.id) == selectedID }
                    viewModel.showSpeciesPicker = false
                }
            )
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
                onSelect: { selectedID in
                    viewModel.selectedSubKind = viewModel.availableSubKinds.first { String($0.id) == selectedID }
                    viewModel.showBreedPicker = false
                }
            )
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
                viewModel.showStorePicker = false
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
        .alert(tr("EditQuantity", "تعديل الكمية"), isPresented: $showQuantityAlert) {
            TextField(tr("LivePetIntake_QuantityLabel", "عدد الحيوانات في المجموعة"), text: $quantityAlertText)
                .englishNumericInput(text: $quantityAlertText, allowsDecimal: false)
            Button(tr("Save", "حفظ")) {
                if let val = Int(quantityAlertText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    viewModel.quantity = max(1, val)
                }
            }
            Button(tr("Cancel", "إلغاء"), role: .cancel) {}
        } message: {
            Text(tr("EnterQuantityPrompt", "أدخل كمية المخزون المتاحة لهذا الصنف"))
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
        Button {
            showJourneyMap = true
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
                                compassStepNumber
                                Spacer(minLength: AdminSpacing.sm)
                                compassCompletionBadge
                            }
                            compassStageCopy
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
                            compassStepNumber
                            compassStageCopy
                            Spacer(minLength: AdminSpacing.sm)
                            compassCompletionBadge
                        }
                    }
                }

                HStack(spacing: AdminSpacing.xs) {
                    ForEach(PPEditorStage.allCases) { stage in
                        Capsule()
                            .fill(progressColor(for: stage))
                            .frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
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
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(viewModel.hasPendingLivePetRecovery)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            format: tr("LivePetIntake_ProgressAccessibility", "الخطوة %ld من 4، %@"),
            viewModel.activeStage.rawValue + 1,
            stageTitle(viewModel.activeStage)
        ))
        .accessibilityHint(tr("LivePetIntake_JourneyMapHint", "يفتح جميع الخطوات وحالة اكتمالها"))
    }

    private var compassStepNumber: some View {
        Text(String(format: "%02d", viewModel.activeStage.rawValue + 1))
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 24 : 32, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AdminSurface.primary)
    }

    private var compassStageCopy: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
            Text(stageTitle(viewModel.activeStage))
                .font(AdminType.title2)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
            Text(stageQuestion(viewModel.activeStage))
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("LivePetIntake_NameLabel", "اسم الحيوان أو الصنف"), required: true)
                    TextField(tr("LivePetIntake_NamePlaceholder", "مثال: كوكتيل لوتينو أليف"), text: $viewModel.name)
                        .font(AdminType.body)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .description }
                        .padding(.horizontal, AdminSpacing.md)
                        .frame(minHeight: AdminTouchTarget.expanded)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .name))
                        .accessibilityLabel(tr("LivePetIntake_NameLabel", "اسم الحيوان أو الصنف"))
                }

                taxonomyControls

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("LivePetIntake_DescriptionLabel", "وصف مختصر"), required: false)
                    ZStack(alignment: .topLeading) {
                        if viewModel.desc.isEmpty {
                            Text(tr("LivePetIntake_DescriptionPlaceholder", "السلوك، اللون، السمات التي يحتاج العميل إلى معرفتها…"))
                                .font(AdminType.body)
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.65))
                                .padding(.horizontal, AdminSpacing.md)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $viewModel.desc)
                            .font(AdminType.body)
                            .focused($focusedField, equals: .description)
                            .frame(minHeight: 112)
                            .padding(AdminSpacing.xs)
                            .scrollContentBackgroundIfAvailable()
                    }
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(fieldFocusBorder(focusedField == .description))
                    .accessibilityLabel(tr("LivePetIntake_DescriptionLabel", "وصف مختصر"))
                }
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
                        Text("\(readyCount)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(blocked == 0 ? Color(uiColor: .ppSuccess) : AdminSurface.primaryText)
                        Text("/\(total)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    String(format: tr("LivePetIntake_BlockedCount", "%ld حيوانات تنتظر بيانات ناقصة"), blocked),
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
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                Text("\(count)/100")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
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

    /// Derived, per-animal completeness. Mirrors the required-field set that
    /// `validate()` and the Infra unit validator already enforce; it does not
    /// add or relax a rule. Gender is deliberately *not* required, because the
    /// server contract defaults an unsent gender to `UNSPECIFIED`.
    private struct PPUnitReadiness {
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

                    Text(ring.isEmpty ? tr("LivePetIntake_IdentifierMissing", "الهوية مطلوبة") : ring)
                        .font(ring.isEmpty
                            ? AdminType.calloutBold
                            : .system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(ring.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                        .environment(\.layoutDirection, ring.isEmpty && Language.isRTL() ? .rightToLeft : .leftToRight)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: AdminSpacing.xs) {
                        genderTag(unit.gender)

                        if isPositiveMoney(unit.sellingPriceText) {
                            Text(String(
                                format: tr("LivePetIntake_UnitPriceFormat", "%@ ر.ق"),
                                unit.sellingPriceText
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
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
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
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
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
        VStack(alignment: .leading, spacing: AdminSpacing.lg) {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                passportSectionHeader(
                    sequence: 1,
                    symbol: "viewfinder.circle.fill",
                    title: tr("LivePetIntake_PassportIdentityTitle", "إشارة الهوية"),
                    subtitle: tr(
                        "LivePetIntake_PassportIdentitySubtitle",
                        "صورة تشغيلية وهوية فريدة تميّزان هذا الحيوان عن بقية الدفعة."
                    )
                )

                identityCaptureLayout(unit: unit, binding: binding, readiness: readiness)
                unitGenderSelector(unit: unit)
            }

            passportSectionDivider

            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                passportSectionHeader(
                    sequence: 2,
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: tr("LivePetIntake_PassportCommercialTitle", "الإحداثيات التجارية"),
                    subtitle: tr(
                        "LivePetIntake_PassportCommercialSubtitle",
                        "قيم البيع والاستلام تخص هذا الحيوان وحده."
                    )
                )
                moneyFields(unit: unit, binding: binding)
            }

            passportSectionDivider

            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                passportSectionHeader(
                    sequence: 3,
                    symbol: "clock.arrow.circlepath",
                    title: tr("LivePetIntake_PassportProvenanceTitle", "سياق الوصول"),
                    subtitle: tr(
                        "LivePetIntake_PassportProvenanceSubtitle",
                        "متى وصل الحيوان ومن أين، مع ملاحظات الفريق الداخلية."
                    )
                )

                receivedDateField(binding: binding)

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

    @ViewBuilder
    private func identityCaptureLayout(
        unit: PPLivePetUnitDraft,
        binding: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                unitPhotoCard(unit: unit)
                identityField(unit: unit, binding: binding, readiness: readiness)
            }
        } else {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                unitPhotoCard(unit: unit)
                    .frame(width: 124)
                identityField(unit: unit, binding: binding, readiness: readiness)
            }
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
                            VStack(spacing: AdminSpacing.xs) {
                                Image(systemName: canAttach ? "camera.aperture" : "lock.fill")
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(canAttach ? AdminSurface.primary : AdminSurface.secondaryText)
                                Text(tr("LivePetIntake_UnitPhotoAdd", "أضف صورة"))
                                    .font(AdminType.captionBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(tr("LivePetIntake_Optional", "اختياري"))
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .multilineTextAlignment(.center)
                            .padding(AdminSpacing.sm)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 178 : 138)
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(
                                photo == nil ? AdminSurface.primary.opacity(0.30) : AdminSurface.hairline,
                                style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [5, 4] : [])
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
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
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                            .background(Color.black.opacity(0.58), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                    .accessibilityLabel(tr("LivePetIntake_UnitPhotoRemove", "إزالة صورة هذا الحيوان"))
                    .accessibilityHint(tr("LivePetIntake_UnitPhotoRemoveHint", "يزيل الصورة المحلية قبل حفظ الإدخال"))
                }
            }

            Button {
                presentUnitPhotoSource(for: unit.id)
            } label: {
                Label(
                    photo == nil
                        ? tr("LivePetIntake_UnitPhotoChoose", "اختيار صورة")
                        : tr("LivePetIntake_UnitPhotoReplace", "استبدال الصورة"),
                    systemImage: photo == nil ? "plus" : "arrow.triangle.2.circlepath"
                )
                .font(AdminType.captionBold)
                .foregroundStyle(canAttach ? AdminSurface.primary : AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                .background(AdminSurface.primary.opacity(canAttach ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            }
            .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            .disabled(!canAttach)

            Label(
                tr("LivePetIntake_UnitPhotoInternalNote", "ترتبط بسجل هذا الحيوان فقط"),
                systemImage: "link.badge.plus"
            )
            .font(AdminType.caption2)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func passportSectionHeader(
        sequence: Int,
        symbol: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.09))
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                    Text(String(format: "%02d", sequence))
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AdminSurface.primary)
                        .environment(\.layoutDirection, .leftToRight)
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(subtitle)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var passportSectionDivider: some View {
        Rectangle()
            .fill(AdminSurface.hairline.opacity(0.72))
            .frame(height: 0.75)
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
                .font(.system(size: 17, weight: .bold, design: .monospaced))
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
            .font(.system(size: 18, weight: .bold, design: .rounded))
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
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                Image(systemName: "allergens.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(tr("LivePetIntake_UnitGender", "جنس هذا الحيوان"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AdminSpacing.xs)
                if unit.gender == .unspecified {
                    Text(tr("LivePetIntake_GenderUnsetNote", "سيُحفظ كغير محدد"))
                        .font(AdminType.caption2)
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.xs) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: false)
                        }
                    }
                } else {
                    HStack(spacing: AdminSpacing.xs) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: true)
                        }
                    }
                }
            }
            .padding(AdminSpacing.xs)
            .background(AdminSurface.primaryText.opacity(0.025), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
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
                    VStack(spacing: 4) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                        Text(option.localizedShortTitle)
                            .font(AdminType.caption2Bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(option.localizedTitle)
                            .font(AdminType.calloutBold)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .padding(.horizontal, AdminSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .leading)
                }
            }
            .foregroundStyle(selected ? tint : AdminSurface.primaryText)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .fill(AdminSurface.surface)
                    if selected {
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .fill(tint.opacity(0.13))
                            .matchedGeometryEffect(id: unit.id, in: genderSelectionNamespace)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.48) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
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

        return VStack(spacing: AdminSpacing.sm) {
            if hasNext || viewModel.livePetUnits.count < 100 {
                Button {
                    advanceFromUnit(at: index)
                } label: {
                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: hasNext ? "arrow.forward.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(hasNext
                            ? tr("LivePetIntake_NextAnimal", "الحيوان التالي")
                            : tr("LivePetIntake_AddAnimal", "إضافة حيوان آخر"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                .accessibilityHint(hasNext
                    ? tr("LivePetIntake_NextAnimalHint", "يطوي هذا الجواز ويفتح الجواز التالي")
                    : tr("LivePetIntake_AddAnimalHint", "ينشئ جواز إدخال فارغاً جديداً"))
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AdminSpacing.xs) {
                        cloneUnitButton(unit)
                        removeUnitButton(unit.id)
                    }
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        cloneUnitButton(unit)
                        removeUnitButton(unit.id)
                    }
                }
            }
        }
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
            Label(tr("LivePetIntake_Clone", "نسخ كحيوان جديد"), systemImage: "plus.square.on.square")
                .font(AdminType.captionBold)
                .foregroundStyle(Color(uiColor: .ppSuccess))
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
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
            Label(tr("LivePetIntake_Remove", "إزالة"), systemImage: "trash")
                .font(AdminType.captionBold)
                .foregroundStyle(isOnlyAnimal ? AdminSurface.secondaryText : Color(uiColor: .ppError))
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                .background(
                    (isOnlyAnimal ? AdminSurface.hairline.opacity(0.25) : Color(uiColor: .ppError).opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
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

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                Text(caption)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if required {
                    Circle()
                        .fill(Color(uiColor: .ppError))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                } else if let optionalNote {
                    Text(optionalNote)
                        .font(AdminType.caption2)
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: AdminSpacing.sm) {
                control()

                if let trailingAffix {
                    Text(trailingAffix)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, AdminSpacing.xs)
                        .padding(.vertical, 3)
                        .background(AdminSurface.primaryText.opacity(0.06), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
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

                Text("\(viewModel.quantity)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String(
                        format: tr("LivePetIntake_QuantityAccessibility", "الكمية %ld"),
                        viewModel.quantity
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        quantityAlertText = "\(viewModel.quantity)"
                        showQuantityAlert = true
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
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 24, weight: .bold, design: .rounded))
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
                    Text(viewModel.customerFacingPriceText)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 28 : 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primary)
                        .monospacedDigit()
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
                Text(String(
                    format: tr("LivePetIntake_SavingsFormat", "وفر العميل %.2f ر.ق"),
                    viewModel.basePrice - viewModel.calculatedFinalPrice
                ))
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
                .font(.system(size: 18, weight: .semibold, design: .rounded))
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
                Text("\(viewModel.livePetUnits.count)")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }

            ForEach(Array(viewModel.livePetUnits.enumerated()), id: \.element.id) { index, unit in
                HStack(spacing: AdminSpacing.sm) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(unit.ringTag.isEmpty
                        ? tr("LivePetIntake_IdentifierMissing", "الهوية مطلوبة")
                        : unit.ringTag)
                        .font(unit.ringTag.isEmpty ? AdminType.caption : .system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(unit.ringTag.isEmpty ? Color(uiColor: .ppWarning) : AdminSurface.primaryText)
                        .environment(\.layoutDirection, unit.ringTag.isEmpty && Language.isRTL() ? .rightToLeft : .leftToRight)
                        .lineLimit(1)
                    Spacer()
                    Text(unit.sellingPriceText.isEmpty
                        ? "—"
                        : String(format: tr("LivePetIntake_UnitPriceFormat", "%@ ر.ق"), unit.sellingPriceText))
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
                Text(String(format: "%.1f%%  •  +%.2f %@", telemetry.marginPercent, telemetry.netProfit, tr("QAR", "ر.ق")))
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

                Text(viewModel.customerFacingPriceText)
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
            if let firstURL = viewModel.existingImageURLs.first, let url = URL(string: firstURL) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 88, height: 88)) {
                    mediaPlaceholder(symbol: "pawprint.fill")
                }
                .frame(width: 88, height: 88)
                .clipped()
            } else if let first = viewModel.pickedImages.first {
                Image(uiImage: first)
                    .resizable()
                    .scaledToFill()
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
                value: viewModel.selectedMainKind?.kindName ?? tr("LivePetIntake_NotComplete", "غير مكتمل"),
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
            if viewModel.desc.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 4_000 {
                return tr("LivePetIntake_ValidationDescriptionLength", "يجب ألا يتجاوز الوصف 4000 حرف.")
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
        if validationMessage(for: stage) == nil { return Color(uiColor: .ppSuccess) }
        return AdminSurface.hairline
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
                    Text(String(format: "%02d", stage.rawValue + 1))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
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
}

private struct PPLivePetChoiceSheet: View {
    let title: String
    let subtitle: String
    let searchPrompt: String
    let emptyTitle: String
    let selectedID: String?
    let choices: [PPLivePetChoice]
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
                                ForEach(filteredChoices) { choice in
                                    choiceRow(choice)
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.lg)
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
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func choiceRow(_ choice: PPLivePetChoice) -> some View {
        let selected = choice.id == selectedID
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect(choice.id)
            dismiss()
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
}

private struct PPLivePetPreviewMedia: Identifiable {
    enum Source {
        case local(UIImage)
        case remote(URL)
    }

    let id = UUID()
    let source: Source
}

private struct PPLivePetMediaPreview: View {
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

private struct PPLivePetPhotoPicker: UIViewControllerRepresentable {
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

private struct PPLivePetCameraPicker: UIViewControllerRepresentable {
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

private struct PPLivePetPressStyle: ButtonStyle {
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
    }

    var body: some View {
        ZStack {
            catalogBackground

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        catalogHeader
                            .accessibilitySortPriority(4)

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
                        .padding(.top, AdminSpacing.sm)
                        .padding(.bottom, AdminSpacing.lg)
                    }
                }
                .scrollDismissesKeyboardCompat()
                .id(viewModel.activeStage)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                catalogActionDock
                    .accessibilitySortPriority(1)
            }
            .allowsHitTesting(!viewModel.isSubmitting && !viewModel.hasCompletedSave)
            .disabled(viewModel.hasCompletedSave)
            .accessibilityHidden(viewModel.isSubmitting)

            if viewModel.isSubmitting {
                catalogSubmissionOverlay
                    .transition(.opacity)
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
            PPLivePetChoiceSheet(
                title: tr("CatalogIntake_SelectCategory", "اختر الفئة الرئيسية"),
                subtitle: tr("CatalogIntake_SelectCategorySub", "ابحث في تصنيف الكتالوج المعتمد."),
                searchPrompt: tr("CatalogIntake_SearchCategory", "ابحث عن فئة"),
                emptyTitle: tr("CatalogIntake_NoCategories", "لا توجد فئات مطابقة"),
                selectedID: viewModel.selectedMainKind.map { String($0.id) },
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
                onSelect: { selectedID in
                    viewModel.selectedMainKind = viewModel.availableMainKinds.first { String($0.id) == selectedID }
                    viewModel.showSpeciesPicker = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showBreedPicker) {
            PPLivePetChoiceSheet(
                title: tr("CatalogIntake_SelectSubcategory", "اختر التصنيف الفرعي"),
                subtitle: tr("CatalogIntake_SelectSubcategorySub", "التصنيف الفرعي اختياري ويمكن تغييره لاحقاً."),
                searchPrompt: tr("CatalogIntake_SearchSubcategory", "ابحث عن تصنيف فرعي"),
                emptyTitle: tr("CatalogIntake_NoSubcategories", "لا توجد تصنيفات فرعية مطابقة"),
                selectedID: viewModel.selectedSubKind.map { String($0.id) },
                choices: viewModel.availableSubKinds.map { subkind in
                    PPLivePetChoice(
                        id: String(subkind.id),
                        title: subkind.subKindName,
                        subtitle: nil,
                        symbol: "tag.fill"
                    )
                },
                onSelect: { selectedID in
                    viewModel.selectedSubKind = viewModel.availableSubKinds.first { String($0.id) == selectedID }
                    viewModel.showBreedPicker = false
                }
            )
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
                viewModel.showStorePicker = false
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
        .alert(tr("EditQuantity", "تعديل الكمية"), isPresented: $showQuantityAlert) {
            TextField(tr("CatalogIntake_Quantity", "الكمية المتاحة"), text: $quantityAlertText)
                .englishNumericInput(text: $quantityAlertText, allowsDecimal: false)
            Button(tr("Save", "حفظ")) {
                if let val = Int(quantityAlertText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    viewModel.quantity = max(0, val)
                }
            }
            Button(tr("Cancel", "إلغاء"), role: .cancel) {}
        } message: {
            Text(tr("EnterQuantityPrompt", "أدخل كمية المخزون المتاحة لهذا الصنف"))
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

            Image(systemName: viewModel.isFood ? "fork.knife" : "shippingbox.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .accessibilityHidden(true)
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

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("CatalogIntake_NameLabel", "اسم الصنف"), required: true)
                    TextField(tr("CatalogIntake_NamePlaceholder", "مثال: منتج واضح وسهل البحث"), text: $viewModel.name)
                        .font(AdminType.body)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .description }
                        .padding(.horizontal, AdminSpacing.md)
                        .frame(minHeight: AdminTouchTarget.expanded)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(fieldFocusBorder(focusedField == .name))
                        .accessibilityLabel(tr("CatalogIntake_NameLabel", "اسم الصنف"))
                }

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("CatalogIntake_DescriptionLabel", "الوصف"), required: false)
                    ZStack(alignment: .topLeading) {
                        if viewModel.desc.isEmpty {
                            Text(tr("CatalogIntake_DescriptionPlaceholder", "المزايا، الاستخدام، المقاس أو المعلومات المهمة للعميل…"))
                                .font(AdminType.body)
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.65))
                                .padding(.horizontal, AdminSpacing.md)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $viewModel.desc)
                            .font(AdminType.body)
                            .focused($focusedField, equals: .description)
                            .frame(minHeight: 120)
                            .padding(AdminSpacing.xs)
                            .scrollContentBackgroundIfAvailable()
                    }
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(fieldFocusBorder(focusedField == .description))
                    .accessibilityLabel(tr("CatalogIntake_DescriptionLabel", "الوصف"))
                }

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
                        TextField(tr("CatalogIntake_BarcodePlaceholder", "امسح أو اكتب الباركود"), text: $viewModel.barcode)
                            .font(AdminType.body)
                            .englishNumericInput(text: $viewModel.barcode, allowsDecimal: false)
                            .focused($focusedField, equals: .barcode)
                            .padding(.horizontal, AdminSpacing.md)
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
                    value: viewModel.selectedMainKind?.kindName,
                    placeholder: tr("CatalogIntake_CategoryPlaceholder", "اختر الفئة المطلوبة"),
                    symbol: viewModel.isFood ? "fork.knife" : "shippingbox",
                    required: true,
                    disabled: viewModel.isLoadingKinds
                ) {
                    viewModel.showSpeciesPicker = true
                }

                taxonomyButton(
                    title: tr("CatalogIntake_SubcategoryLabel", "التصنيف الفرعي"),
                    value: viewModel.selectedSubKind?.subKindName,
                    placeholder: viewModel.selectedMainKind == nil
                        ? tr("CatalogIntake_SelectCategoryFirst", "اختر الفئة الرئيسية أولاً")
                        : tr("CatalogIntake_SubcategoryPlaceholder", "اختياري"),
                    symbol: "tag",
                    required: false,
                    disabled: viewModel.selectedMainKind == nil
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

                if !viewModel.isFood {
                    VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                        fieldLabel(tr("CatalogIntake_ConditionLabel", "حالة المنتج"), required: true)
                        Picker(tr("CatalogIntake_ConditionLabel", "حالة المنتج"), selection: $viewModel.condition) {
                            Text(tr("Condition_New", "جديد")).tag(AccessConditions.new)
                            Text(tr("Condition_Used", "مستعمل")).tag(AccessConditions.used)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(tr("CatalogIntake_ConditionLabel", "حالة المنتج"))
                    }
                } else {
                    Label(
                        tr("CatalogIntake_FoodConditionNote", "تُحفظ الأغذية والمكملات دائماً بحالة جديدة."),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(AdminType.footnote)
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: AdminSpacing.md) {
                            weightField
                            weightUnitField
                        }
                    } else {
                        HStack(alignment: .bottom, spacing: AdminSpacing.md) {
                            weightField
                            weightUnitField
                        }
                    }
                }

                if viewModel.isFood {
                    VStack(alignment: .leading, spacing: AdminSpacing.md) {
                        Toggle(isOn: $viewModel.hasExpiryDate) {
                            VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                                Text(tr("CatalogIntake_ExpiryToggle", "للصنف تاريخ انتهاء صلاحية"))
                                    .font(AdminType.calloutBold)
                                Text(tr("CatalogIntake_ExpiryHint", "فعّلها عندما تكون الصلاحية مطبوعة على العبوة."))
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                        .tint(AdminSurface.primary)

                        if viewModel.hasExpiryDate {
                            DatePicker(
                                tr("CatalogIntake_ExpiryDate", "تاريخ انتهاء الصلاحية"),
                                selection: $viewModel.expiryDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .font(AdminType.callout)
                            .frame(minHeight: AdminTouchTarget.minimum)
                        }
                    }
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                }
            }
        }
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("CatalogIntake_WeightLabel", "الوزن أو الحجم"), required: false)
            TextField("0.0", text: $viewModel.weightText)
                .font(AdminType.headline)
                .englishNumericInput(text: $viewModel.weightText, allowsDecimal: true)
                .focused($focusedField, equals: .weight)
                .padding(.horizontal, AdminSpacing.md)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(fieldFocusBorder(focusedField == .weight))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightUnitField: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            fieldLabel(tr("CatalogIntake_UnitLabel", "الوحدة"), required: false)
            Picker(tr("CatalogIntake_UnitLabel", "الوحدة"), selection: $viewModel.weightUnit) {
                Text("kg").tag("kg")
                Text("g").tag("g")
                Text("L").tag("L")
                Text("ml").tag("ml")
            }
            .pickerStyle(.menu)
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded, alignment: .leading)
            .padding(.horizontal, AdminSpacing.md)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(String(format: "%.2f %@", viewModel.calculatedFinalPrice, tr("QAR", "ر.ق")))
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

                Divider().background(AdminSurface.hairline)

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    fieldLabel(tr("CatalogIntake_Quantity", "الكمية المتاحة"), required: true)
                    HStack(spacing: AdminSpacing.md) {
                        quantityButton(symbol: "minus", enabled: viewModel.quantity > 0) {
                            viewModel.quantity = max(0, viewModel.quantity - 1)
                        }
                        Text("\(viewModel.quantity)")
                            .font(AdminType.title)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(String(
                                format: tr("CatalogIntake_QuantityAccessibility", "الكمية %ld"),
                                viewModel.quantity
                            ))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                quantityAlertText = "\(viewModel.quantity)"
                                showQuantityAlert = true
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
                        symbol: "square.grid.2x2.fill",
                        title: tr("CatalogIntake_ReviewCategory", "الفئة"),
                        value: viewModel.selectedMainKind?.kindName ?? tr("CatalogIntake_NotSet", "غير محدد")
                    )
                    reviewRow(
                        symbol: "tag.fill",
                        title: tr("CatalogIntake_ReviewPrice", "السعر النهائي"),
                        value: String(format: "%.2f %@", viewModel.calculatedFinalPrice, tr("QAR", "ر.ق")),
                        forceLTR: true
                    )
                    reviewRow(
                        symbol: "number.square.fill",
                        title: tr("CatalogIntake_ReviewQuantity", "الكمية"),
                        value: "\(viewModel.quantity)",
                        forceLTR: true
                    )
                    if viewModel.isFood && viewModel.hasExpiryDate {
                        reviewRow(
                            symbol: "calendar.badge.clock",
                            title: tr("CatalogIntake_ReviewExpiry", "انتهاء الصلاحية"),
                            value: viewModel.expiryDate.formatted(date: .abbreviated, time: .omitted)
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
            Text(value)
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
                } else {
                    Image(systemName: viewModel.activeStage == .governance
                        ? (viewModel.isDraft ? "doc.badge.plus" : "checkmark.shield.fill")
                        : "arrow.forward")
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
