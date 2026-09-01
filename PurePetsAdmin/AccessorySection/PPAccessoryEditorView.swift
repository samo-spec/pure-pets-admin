//
//  PPAccessoryEditorView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Preserves 100% backend contract parity with PetAccessory, AccessoryManager,
//  Firebase Storage, and AppManager while elevating the presentation layer.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Sendable Conformance

extension MainKindsModel: @unchecked Sendable {}
extension SubKindModel: @unchecked Sendable {}

// MARK: - View Model

@MainActor
final class PPAccessoryEditorViewModel: ObservableObject {
    // MARK: - Public Inputs & Identity
    let editingAccessory: PetAccessory?
    let showTypeRow: Bool
    let onDismiss: () -> Void

    // MARK: - Form State
    @Published var selectedKind: AccessKindType {
        didSet {
            if selectedKind == .typeFood {
                condition = .new
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
    
    // Inventory & Stock
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
    
    // UI Lifecycle & Async States
    @Published var availableMainKinds: [MainKindsModel] = []
    @Published var isLoadingKinds: Bool = false
    @Published var kindsErrorMessage: String? = nil
    
    @Published var isSubmitting: Bool = false
    @Published var submitProgress: Double = 0.0
    @Published var saveSuccessMessage: String? = nil
    @Published var errorMessage: String? = nil
    @Published var hasUnsavedChanges: Bool = false
    
    // Active Modals
    @Published var showImagePicker: Bool = false
    @Published var showSpeciesPicker: Bool = false
    @Published var showBreedPicker: Bool = false
    @Published var showStorePicker: Bool = false
    @Published var previewImageURL: String? = nil
    @Published var previewUIImage: UIImage? = nil
    @Published var showDiscardConfirmation: Bool = false

    private var initialSetupComplete: Bool = false
    private var liveCreateCommandID = PPLivePetInventoryService.commandID("catalog-create")

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
        loadMainKinds()
    }

    // MARK: - Populate Data

    private func populateInitialValues() {
        guard let acc = editingAccessory else {
            selectedStoreID = "main_store"
            selectedStoreName = Language.get("Main Store", alter: "المتجر الرئيسي")
            initialSetupComplete = true
            return
        }

        name = acc.name ?? ""
        desc = acc.desc ?? ""
        
        let price = acc.price
        if price.doubleValue > 0 {
            priceText = String(format: "%g", price.doubleValue)
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
        
        if let exp = acc.expiryDate {
            hasExpiryDate = true
            expiryDate = exp
        }

        weightText = acc.weightText ?? ""

        selectedStoreID = (acc.storeID ?? "").isEmpty == false ? acc.storeID! : "main_store"
        selectedStoreName = (acc.storeName ?? "").isEmpty == false ? acc.storeName! : Language.get("Main Store", alter: "المتجر الرئيسي")
        
        isDraft = !acc.active
        existingImageURLs = acc.imageURLsArray ?? []
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.initialSetupComplete = true
            self?.hasUnsavedChanges = false
        }
    }

    private func setupStoreOptions() {
        var options: [(id: String, name: String)] = []
        let mainName = Language.get("Main Store", alter: "المتجر الرئيسي")
        options.append(("main_store", mainName))
        
        if let currentUID = Auth.auth().currentUser?.uid, !currentUID.isEmpty, currentUID != "main_store" {
            let myName = Auth.auth().currentUser?.displayName ?? Language.get("My Store", alter: "متجري")
            options.append((currentUID, myName.isEmpty ? Language.get("My Store", alter: "متجري") : myName))
        }
        
        if let existingID = editingAccessory?.storeID, !existingID.isEmpty, !options.contains(where: { $0.id == existingID }) {
            let existingName = editingAccessory?.storeName ?? existingID
            options.append((existingID, existingName))
        }
        
        self.availableStores = options
        if selectedStoreName.isEmpty {
            selectedStoreName = options.first?.name ?? mainName
        }
    }

    // MARK: - MainKinds & Breeds Fetching

    func loadMainKinds() {
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            self.matchSelectedCategories()
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
            }
        }
    }

    private func matchSelectedCategories() {
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
    var canViewStockCosts: Bool {
        PPStaffAuth.shared().cachedCurrentStaff?.hasPermission("stock.cost.view") ?? false
    }

    var groupCost: Double {
        let clean = liveGroupCostText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return max(0, Double(clean) ?? 0)
    }

    func addLivePetUnit() {
        guard !isEditingLivePet, livePetUnits.count < 100 else { return }
        livePetUnits.append(PPLivePetUnitDraft(sellingPriceText: priceText, supplier: liveSupplier))
        quantity = livePetUnits.count
    }

    func removeLivePetUnit(id: String) {
        guard !isEditingLivePet, livePetUnits.count > 1 else { return }
        livePetUnits.removeAll { $0.id == id }
        quantity = livePetUnits.count
    }

    func selectLiveInventoryMode(_ mode: PPLivePetInventoryMode) {
        guard !isEditingLivePet else { return }
        liveInventoryMode = mode
        if mode == .individual {
            if livePetUnits.isEmpty {
                livePetUnits = [PPLivePetUnitDraft(sellingPriceText: priceText, supplier: liveSupplier)]
            }
            quantity = livePetUnits.count
        }
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
        let clean = priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(clean) ?? 0.0
    }

    var discountPercent: Double {
        let clean = discountPercentText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let val = Double(clean) ?? 0.0
        return min(100.0, max(0.0, val))
    }

    var discountAmount: Double {
        let clean = discountAmountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let val = Double(clean) ?? 0.0
        return max(0.0, val)
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
        let currencySymbol = Language.get("QAR", alter: "ر.ق")
        if calculatedFinalPrice == floor(calculatedFinalPrice) {
            return String(format: "%.0f %@", calculatedFinalPrice, currencySymbol)
        }
        return String(format: "%.2f %@", calculatedFinalPrice, currencySymbol)
    }

    // MARK: - Image Operations

    func addPickedImages(_ images: [UIImage]) {
        for image in images {
            guard canAddImages else { break }
            pickedImages.append(image)
        }
    }

    func removeExistingImage(at index: Int) {
        guard index >= 0 && index < existingImageURLs.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        existingImageURLs.remove(at: index)
    }

    func removePickedImage(at index: Int) {
        guard index >= 0 && index < pickedImages.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pickedImages.remove(at: index)
    }

    private func updateUnsavedChanges() {
        guard initialSetupComplete else { return }
        hasUnsavedChanges = true
        errorMessage = nil
    }

    // MARK: - Validation

    func validate() -> (isValid: Bool, message: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || basePrice <= 0 {
            return (false, Language.get("Name and price are required.", alter: "يرجى إدخال اسم وسعر المنتج"))
        }
        if selectedMainKind == nil {
            return (false, Language.get("Please select pet species.", alter: "يرجى اختيار النوع (الفئة الرئيسية)"))
        }
        if isLivePet {
            if liveInventoryMode == .quantity, quantity < 1 {
                return (false, Language.get("LivePet_Validation_GroupQuantity", alter: "أدخل كمية صحيحة لا تقل عن حيوان واحد للمجموعة."))
            }
            if liveInventoryMode == .individual && editingAccessory == nil {
                guard !livePetUnits.isEmpty else {
                    return (false, Language.get("LivePet_Validation_UnitRequired", alter: "أضف سجلاً واحداً على الأقل لحيوان محدد."))
                }
                let normalizedRings = livePetUnits.map {
                    $0.ringTag.precomposedStringWithCompatibilityMapping
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .lowercased(with: Locale(identifier: "en_US_POSIX"))
                }
                if normalizedRings.contains(where: { $0.isEmpty || $0.count > 80 }) {
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
        guard !isSubmitting else { return }
        
        let (isValid, validationMessage) = validate()
        guard isValid else {
            errorMessage = validationMessage
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSubmitting = true
        errorMessage = nil
        saveSuccessMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let accessory = editingAccessory ?? PetAccessory()
        accessory.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accessory.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        accessory.storeID = selectedStoreID.isEmpty ? "main_store" : selectedStoreID
        accessory.storeName = selectedStoreName.isEmpty ? Language.get("Main Store", alter: "المتجر الرئيسي") : selectedStoreName

        if !weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accessory.weightText = "\(weightText.trimmingCharacters(in: .whitespacesAndNewlines)) \(weightUnit)"
        }
        
        accessory.expiryDate = hasExpiryDate ? expiryDate : nil
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

        // Upload newly picked images
        if pickedImages.isEmpty {
            accessory.imageURLsArray = currentExistingURLs
            finalizeAccessorySave(accessory: accessory, oldImageURLs: oldImageURLs)
        } else {
            uploadNewImages(images: pickedImages) { [weak self] uploadedURLs, metaArray, uploadError in
                guard let self = self else { return }
                if let err = uploadError {
                    self.isSubmitting = false
                    self.errorMessage = err.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                let finalURLs = currentExistingURLs + (uploadedURLs ?? [])
                accessory.imageURLsArray = finalURLs
                accessory.imageMeta = metaArray
                self.finalizeAccessorySave(accessory: accessory, oldImageURLs: oldImageURLs)
            }
        }
    }

    private func uploadNewImages(
        images: [UIImage],
        completion: @escaping ([String]?, [[AnyHashable: Any]]?, Error?) -> Void
    ) {
        let storageRef = Storage.storage().reference()
        let group = DispatchGroup()
        var uploadedURLs: [String] = []
        var metaArray: [[AnyHashable: Any]] = []
        var firstError: Error?
        let lock = NSLock()

        for image in images {
            guard let data = image.pngData() else { continue }
            group.enter()
            let uuid = UUID().uuidString
            let imgRef = storageRef.child("petAccessories").child("\(uuid).png")
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/png"
            metadata.customMetadata = [
                "uploaded_by": Auth.auth().currentUser?.uid ?? "",
                "entity_type": "accessory",
                "media_type": "image"
            ]

            imgRef.putData(data, metadata: metadata) { _, error in
                if let err = error {
                    lock.lock()
                    if firstError == nil { firstError = err }
                    lock.unlock()
                    group.leave()
                    return
                }

                imgRef.downloadURL { url, error2 in
                    lock.lock()
                    if let u = url?.absoluteString {
                        uploadedURLs.append(u)
                        let meta: [AnyHashable: Any] = [
                            "url": u,
                            "width": Double(image.size.width),
                            "height": Double(image.size.height)
                        ]
                        metaArray.append(meta)
                    }
                    if let err2 = error2, firstError == nil {
                        firstError = err2
                    }
                    lock.unlock()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if let err = firstError {
                completion(nil, nil, err)
            } else {
                completion(uploadedURLs, metaArray, nil)
            }
        }
    }

    private func finalizeAccessorySave(accessory: PetAccessory, oldImageURLs: [String]) {
        if isLivePet {
            finalizeLivePetSave(accessory: accessory, oldImageURLs: oldImageURLs)
            return
        }
        AccessoryManager.shared().createOrUpdate(accessory) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSubmitting = false
                
                if let err = error {
                    self.errorMessage = err.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
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

                self.hasUnsavedChanges = false
                self.saveSuccessMessage = (self.editingAccessory != nil)
                    ? Language.get("Your changes were saved successfully.", alter: "تم حفظ التعديلات بنجاح")
                    : Language.get("Accessory has been created.", alter: "تمت إضافة الصنف بنجاح")
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.onDismiss()
                }
            }
        }
    }

    private func finalizeLivePetSave(accessory: PetAccessory, oldImageURLs: [String]) {
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
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        // Quantity-tracked live pets keep the same catalog discount contract
        // as Console. Individually tracked parents are projected from exact
        // unit prices and must never be overwritten with a parent discount.
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
                "acquisitionDate": ISO8601DateFormatter().string(from: unit.acquisitionDate),
                "purchaseCost": purchaseCost ?? NSNull(),
                "sellingPrice": sellingPrice,
                "supplier": unit.supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "notes": unit.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "mediaURLs": [],
            ]
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if productID.isEmpty {
                    var payload: [String: Any] = [
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
                        payload["standardSellingPrice"] = basePrice
                    }
                    let createResponse = try await PPLivePetInventoryService.callInventory(
                        action: "create",
                        commandID: liveCreateCommandID,
                        payload: payload
                    )
                    let createdProductID = PPLivePetInventoryService.string(createResponse["productId"])
                    guard !createdProductID.isEmpty else {
                        throw PPLivePetServiceError.invalidResponse
                    }
                    try await PPLivePetInventoryService.updateCatalogPresentation(
                        productID: createdProductID,
                        values: catalogValues
                    )
                } else {
                    if liveInventoryMode == .individual {
                        _ = try await PPLivePetInventoryService.callInventory(
                            action: "update_standard_selling_price",
                            productID: productID,
                            commandID: PPLivePetInventoryService.commandID("standard-selling-price"),
                            payload: ["standardSellingPrice": basePrice]
                        )
                    } else {
                        _ = try await PPLivePetInventoryService.callInventory(
                            action: "update",
                            productID: productID,
                            payload: [
                                "quantity": max(0, quantity),
                                "price": basePrice,
                                "finalPrice": calculatedFinalPrice,
                            ]
                        )
                    }
                    try await PPLivePetInventoryService.updateCatalogPresentation(
                        productID: productID,
                        values: catalogValues
                    )
                }

                cleanupRemovedImages(oldImageURLs: oldImageURLs, retainedURLs: accessory.imageURLsArray ?? [])
                isSubmitting = false
                hasUnsavedChanges = false
                saveSuccessMessage = editingAccessory == nil
                    ? Language.get("LivePet_Create_Success", alter: "تم إنشاء سجل الحيوان والمخزون بنجاح.")
                    : Language.get("LivePet_Update_Success", alter: "تم تحديث بيانات الكتالوج والمخزون بنجاح.")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.onDismiss() }
            } catch {
                isSubmitting = false
                errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
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

// MARK: - Reimagined Flagship Accessory & Live Pet Editor View

struct PPAccessoryEditorScreen: View {
    @StateObject var viewModel: PPAccessoryEditorViewModel
    @FocusState private var focusedField: FormField?
    
    enum FormField: Hashable {
        case name, desc, price, discountPercent, discountAmount, quantity, ringTag, passport, weight
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    sovereignHeaderView

                    if viewModel.showTypeRow && viewModel.editingAccessory == nil {
                        archetypeSelectorDeck
                    }

                    heroLivePreviewCard
                    mediaAssetVaultDeck
                    coreInformationDeck
                    taxonomyClassificationDeck
                    
                    if viewModel.isLivePet {
                        livePetBioSecurityDeck
                    }

                    financialPricingDeck
                    inventoryLogisticsDeck

                    if viewModel.isFood {
                        expiryDateDeck
                    }

                    storeAllocationDeck
                    publishingStateDeck
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }

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
            PPAccessoryStorePickerSheet(
                stores: viewModel.availableStores,
                selectedStoreID: viewModel.selectedStoreID,
                onSelect: { storeID, storeName in
                    viewModel.selectedStoreID = storeID
                    viewModel.selectedStoreName = storeName
                    viewModel.showStorePicker = false
                }
            )
        }
        .alert(Language.get("Warning", alter: "تنبيه"), isPresented: $viewModel.showDiscardConfirmation) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) { }
            Button(Language.get("Discard Changes", alter: "مغادرة وتجاهل"), role: .destructive) {
                viewModel.onDismiss()
            }
        } message: {
            Text(Language.get("Are you sure you want to discard unsaved changes?", alter: "هل أنت متأكد من رغبتك في المغادرة؟ ستفقد كافة التعديلات غير المحفوظة."))
        }
    }

    // MARK: - Sovereign Header

    private var sovereignHeaderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: {
                    if viewModel.hasUnsavedChanges {
                        viewModel.showDiscardConfirmation = true
                    } else {
                        viewModel.onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )
                }
                .buttonStyle(EditorPressStyle())

                Spacer()

                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(AdminSurface.primary)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                            .frame(width: 7, height: 7)
                        Text(viewModel.isDraft ? Language.get("Draft", alter: "مسودة") : Language.get("Active", alter: "نشط بالمنصة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (viewModel.isDraft ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)).opacity(0.10),
                        in: Capsule(style: .continuous)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("CommandCenter_Inventory_Workspace", alter: "مساحة المخزون والكتالوج") + " / " + viewModel.eyebrowKindText)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminCommandInk.secondary)

                Text(viewModel.screenTitle)
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.top, 2)

            if let err = viewModel.errorMessage {
                AdminErrorBanner(message: err) {
                    viewModel.errorMessage = nil
                }
                .padding(.top, 4)
            } else if let success = viewModel.saveSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(uiColor: .ppSuccess))
                    Text(success)
                        .font(AdminType.calloutBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Archetype Selector

    private var archetypeSelectorDeck: some View {
        HStack(spacing: 8) {
            archetypePill(kind: .typeAccessory, title: Language.get("Accessory", alter: "إكسسوار"), icon: "bag.fill")
            archetypePill(kind: .typeFood, title: Language.get("Food", alter: "أغذية ومكملات"), icon: "fork.knife")
            archetypePill(kind: .typeLivePets, title: Language.get("Live pets", alter: "حيوان أليف حي"), icon: "pawprint.fill")
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

    // MARK: - Live Hologram Preview Card

    private var heroLivePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("LiveConsumerPreview", alter: "معاينة الصنف في التطبيق والـ POS"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Image(systemName: "iphone")
                    .font(.system(size: 11))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            HStack(spacing: 14) {
                // Photo Preview
                ZStack {
                    if let firstPicked = viewModel.pickedImages.first {
                        Image(uiImage: firstPicked)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if let firstURL = viewModel.existingImageURLs.first, let url = URL(string: firstURL) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "photo.fill").foregroundStyle(AdminCommandInk.tertiary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.control)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: viewModel.isLivePet ? "pawprint.fill" : (viewModel.isFood ? "fork.knife" : "bag.fill"))
                                    .font(.system(size: 22))
                                    .foregroundStyle(AdminSurface.primary.opacity(0.6))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(viewModel.selectedMainKind?.kindName ?? Language.get("General", alter: "عام"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))

                        if let breed = viewModel.selectedSubKind?.subKindName {
                            Text("• \(breed)")
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                    }

                    Text(viewModel.name.isEmpty ? Language.get("ItemNamePlaceholder", alter: "اسم المنتج أو الحيوان") : viewModel.name)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 0.75)
        )
    }

    // MARK: - Media Asset Vault

    private var mediaAssetVaultDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("MediaVault", alter: "معرض الصور والوسائط"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text("\(viewModel.totalImageCount)/9 " + Language.get("Photos", alter: "صور"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Add Photo Button
                    if viewModel.canAddImages {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.showImagePicker = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.badge.ellipsis")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(AdminSurface.primary)
                                Text(Language.get("AddPhoto", alter: "إضافة صورة"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .frame(width: 86, height: 86)
                            .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
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
                                .frame(width: 86, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button {
                                viewModel.removePickedImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white, Color.red)
                                    .padding(4)
                            }
                        }
                    }

                    // Existing URLs
                    ForEach(Array(viewModel.existingImageURLs.enumerated()), id: \.offset) { index, urlString in
                        ZStack(alignment: .topTrailing) {
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: 86, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            Button {
                                viewModel.removeExistingImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
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
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Core Information Deck

    private var coreInformationDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Language.get("CoreInfo", alter: "البيانات الأساسية للصنف"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("ItemName", alter: "اسم الصنف أو الحيوان"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                TextField(Language.get("EnterItemName", alter: "أدخل اسم المنتج بدقة..."), text: $viewModel.name)
                    .font(AdminType.callout)
                    .focused($focusedField, equals: .name)
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .desc ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
                    )
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Taxonomy & Classification

    private var taxonomyClassificationDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Language.get("Taxonomy", alter: "التصنيف والنوع والسلالة"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                // Species Selector
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
                        }
                        Spacer()
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(EditorPressStyle())

                // Breed Selector
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
                        }
                        Spacer()
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(viewModel.selectedMainKind != nil ? AdminSurface.primary : AdminCommandInk.tertiary)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(EditorPressStyle())
                .disabled(viewModel.selectedMainKind == nil)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Live Pet Bio-Security & Lifecycle Deck

    private var livePetBioSecurityDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                }

                Text(Language.get("LivePetBioSecurity", alter: "بيانات الحيوان الحي والشهادة الصحية"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("LivePet_Tracking_Title", alter: "نمط إدارة المخزون الحي"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

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
                        Language.get("LivePet_Tracking_Locked_Hint", alter: "نمط التتبع ثابت بعد الإنشاء. استخدم مساحة عمليات الحيوانات لإضافة الأفراد أو إدارة الحالات."),
                        systemImage: "lock.shield"
                    )
                    .font(AdminType.caption2)
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if viewModel.liveInventoryMode == .individual && !viewModel.isEditingLivePet {
                VStack(spacing: 10) {
                    ForEach($viewModel.livePetUnits) { $unit in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(
                                    Language.get("LivePet_Unit_Record", alter: "سجل حيوان محدد"),
                                    systemImage: "number.circle.fill"
                                )
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.primary)

                                Spacer()

                                if viewModel.livePetUnits.count > 1 {
                                    Button(role: .destructive) {
                                        viewModel.removeLivePetUnit(id: unit.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .accessibilityLabel(Language.get("LivePet_Remove_Unit", alter: "إزالة سجل الحيوان"))
                                }
                            }

                            TextField(Language.get("LivePet_Ring_Placeholder", alter: "رقم الحلقة أو الشريحة"), text: $unit.ringTag)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .padding(12)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .environment(\.layoutDirection, .leftToRight)

                            HStack(spacing: 10) {
                                livePetUnitNumberField(
                                    title: Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع"),
                                    text: $unit.sellingPriceText
                                )
                                if viewModel.canViewStockCosts {
                                    livePetUnitNumberField(
                                        title: Language.get("LivePet_Unit_PurchaseCost", alter: "تكلفة الشراء"),
                                        text: $unit.purchaseCostText
                                    )
                                }
                            }

                            DatePicker(
                                Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"),
                                selection: $unit.acquisitionDate,
                                displayedComponents: .date
                            )
                            .font(AdminType.caption1)

                            TextField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد، اختياري"), text: $unit.supplier)
                                .font(AdminType.callout)
                                .padding(12)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            TextField(Language.get("LivePet_Unit_Notes_Placeholder", alter: "ملاحظات داخلية، اختيارية"), text: $unit.notes)
                                .font(AdminType.callout)
                                .padding(12)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(12)
                        .background(AdminSurface.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        viewModel.addLivePetUnit()
                    } label: {
                        Label(Language.get("LivePet_Add_Another_Unit", alter: "إضافة حيوان آخر"), systemImage: "plus.circle.fill")
                            .font(AdminType.captionBold)
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(AdminSurface.primary)
                    .disabled(viewModel.livePetUnits.count >= 100)
                }
            } else if viewModel.liveInventoryMode == .quantity {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if viewModel.canViewStockCosts {
                            livePetUnitNumberField(
                                title: Language.get("LivePet_Group_PurchaseCost", alter: "تكلفة الوحدة"),
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

                    TextField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد، اختياري"), text: $viewModel.liveSupplier)
                        .font(AdminType.callout)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    TextField(Language.get("LivePet_Group_Notes_Placeholder", alter: "ملاحظات إدخال المجموعة، اختيارية"), text: $viewModel.liveIntakeNotes)
                        .font(AdminType.callout)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Gender Selector
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Gender", alter: "الجنس"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 8) {
                    genderPill(id: "male", title: "ذكر ♂", color: Color.blue)
                    genderPill(id: "female", title: "أنثى ♀", color: Color.pink)
                    genderPill(id: "pair", title: "زوج ⚥", color: Color.purple)
                }
            }

            // Bio-Security Switches
            VStack(spacing: 10) {
                Toggle(isOn: $viewModel.isVaccinated) {
                    HStack(spacing: 8) {
                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(Language.get("FullyVaccinated", alter: "ملقح بالكامل ومحصن بيطرياً"))
                            .font(AdminType.callout)
                    }
                }
                .tint(AdminSurface.primary)

                Toggle(isOn: $viewModel.isDewormed) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(Language.get("Dewormed", alter: "معالج ضد الطفيليات والديدان"))
                            .font(AdminType.callout)
                    }
                }
                .tint(AdminSurface.primary)

                Toggle(isOn: $viewModel.isMicrochipped) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(Color.blue)
                        Text(Language.get("Microchipped", alter: "شريحة تعريف إلكترونية دولية"))
                            .font(AdminType.callout)
                    }
                }
                .tint(AdminSurface.primary)
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.3), lineWidth: 0.75)
        )
    }

    private func livePetUnitNumberField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            TextField("0.00", text: text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
    }

    private func genderPill(id: String, title: String, color: Color) -> some View {
        let isSelected = viewModel.selectedGender == id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            viewModel.selectedGender = id
        } label: {
            Text(title)
                .font(AdminType.captionBold)
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    isSelected
                        ? AnyView(Capsule().fill(color))
                        : AnyView(Capsule().fill(AdminSurface.control))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Financial Pricing Deck

    private var financialPricingDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                viewModel.isIndividualLivePet
                    ? Language.get("LivePet_Standard_SellingPrice", alter: "سعر البيع القياسي")
                    : Language.get("PricingAndDiscounts", alter: "التسعير والعروض الترويجية")
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .price)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .environment(\.layoutDirection, .leftToRight)
                }

                if !viewModel.isIndividualLivePet {
                    // Discount Percent
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("DiscountPercent", alter: "الخصم (%)"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)

                        TextField("0", text: $viewModel.discountPercentText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .discountPercent)
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }

            if viewModel.isIndividualLivePet {
                Label(
                    Language.get("LivePet_Standard_SellingPrice_Hint", alter: "يُستخدم هذا السعر افتراضياً للحيوانات الجديدة؛ سعر كل سجل فردي هو المرجع النهائي في نقطة البيع."),
                    systemImage: "info.circle.fill"
                )
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Final Readout Plate
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("FinalCustomerPrice", alter: "السعر النهائي للعميل"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(viewModel.formattedFinalPrice)
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primary)
                }
                Spacer()
                if viewModel.calculatedFinalPrice < viewModel.basePrice && viewModel.basePrice > 0 {
                    Text(String(format: Language.get("DiscountSavings", alter: "وفر %.0f ر.ق"), viewModel.basePrice - viewModel.calculatedFinalPrice))
                        .font(AdminType.captionBold)
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule(style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Inventory Logistics Deck

    private var inventoryLogisticsDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Language.get("StockAndLogistics", alter: "إدارة المخزون والمواصفات"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                // Quantity Stepper
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        viewModel.isIndividualLivePet
                            ? Language.get("LivePet_Registered_Unit_Count", alter: "عدد السجلات الفردية")
                            : Language.get("StockQuantity", alter: "الكمية بالمخزن")
                    )
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    if viewModel.isIndividualLivePet {
                        Text("\(viewModel.editingAccessory?.quantity ?? viewModel.livePetUnits.count)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        HStack(spacing: 6) {
                            Button {
                                if viewModel.quantity > 1 { viewModel.quantity -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .disabled(viewModel.quantity <= 1)

                            Text("\(viewModel.quantity)")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .frame(minWidth: 40)
                                .multilineTextAlignment(.center)

                            Button {
                                viewModel.quantity += 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(4)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.6)))
                    }
                }

                // Condition (if not food)
                if !viewModel.isFood && !viewModel.isLivePet {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Condition", alter: "حالة العنصر"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)

                        Picker(Language.get("Condition", alter: "الحالة"), selection: $viewModel.condition) {
                            Text(Language.get("Condition_New", alter: "جديد")).tag(AccessConditions.new)
                            Text(Language.get("Condition_Used", alter: "مستعمل")).tag(AccessConditions.used)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Expiry Date Deck

    private var expiryDateDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $viewModel.hasExpiryDate) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("HasExpiryDate", alter: "تاريخ انتهاء صلاحية المنتج"))
                        .font(AdminType.headline)
                }
            }
            .tint(AdminSurface.primary)

            if viewModel.hasExpiryDate {
                DatePicker("", selection: $viewModel.expiryDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Store Allocation

    private var storeAllocationDeck: some View {
        Button {
            focusedField = nil
            viewModel.showStorePicker = true
        } label: {
            HStack {
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
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
        .buttonStyle(EditorPressStyle())
    }

    // MARK: - Publishing State

    private var publishingStateDeck: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $viewModel.isDraft) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("SaveAsDraft", alter: "حفظ كمسودة مخفية مؤقتاً"))
                        .font(AdminType.headline)
                    Text(Language.get("DraftDesc", alter: "لن يظهر المنتج للعملاء في التطبيق حتى يتم تفعيله."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
            .tint(Color(uiColor: .ppWarning))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    // MARK: - Tactical Save Dock

    private var tacticalSaveDock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    viewModel.saveAccessory()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16, weight: .bold))
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Divider()
                            .background(Color(uiColor: .ppSurfaceBorder).opacity(0.7))
                    }
            )
        }
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

// MARK: - Modal Pickers

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
            List(filtered, id: \.id) { species in
                Button {
                    onSelect(species)
                    dismiss()
                } label: {
                    HStack {
                        Text(species.kindName)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.primaryText)
                        Spacer()
                        if selectedSpecies?.id == species.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(Language.get("SelectSpecies", alter: "اختر النوع"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                }
            }
        }
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
            List(filtered, id: \.id) { breed in
                Button {
                    onSelect(breed)
                    dismiss()
                } label: {
                    HStack {
                        Text(breed.subKindName)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.primaryText)
                        Spacer()
                        if selectedBreed?.id == breed.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(Language.get("SelectBreed", alter: "اختر السلالة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                }
            }
        }
    }
}

private struct PPAccessoryStorePickerSheet: View {
    let stores: [(id: String, name: String)]
    let selectedStoreID: String
    let onSelect: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(stores, id: \.id) { store in
                Button {
                    onSelect(store.id, store.name)
                    dismiss()
                } label: {
                    HStack {
                        Text(store.name)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.primaryText)
                        Spacer()
                        if selectedStoreID == store.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
            .navigationTitle(Language.get("SelectStore", alter: "اختر المتجر"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                }
            }
        }
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
        let host = UIHostingController(rootView: PPAccessoryEditorScreen(viewModel: viewModel))
        host.view.backgroundColor = .clear
        return host
    }
}
