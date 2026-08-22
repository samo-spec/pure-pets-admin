//
//  PPAccessoryEditorView.swift
//  PurePetsAdmin
//
//  NextGen V6 SwiftUI Architecture for Accessory, Food, and Live Pet Editor.
//  Preserves 100% backend contract parity with PetAccessory, AccessoryManager,
//  Firebase Storage, and AppManager while elevating the presentation layer.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
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
    
    // Pricing
    @Published var priceText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var discountPercentText: String = "" { didSet { updateUnsavedChanges() } }
    @Published var discountAmountText: String = "" { didSet { updateUnsavedChanges() } }
    
    // Inventory & Stock
    @Published var quantity: Int = 0 { didSet { updateUnsavedChanges() } }
    @Published var condition: AccessConditions = .new { didSet { updateUnsavedChanges() } }
    
    // Expiry Date
    @Published var hasExpiryDate: Bool = false { didSet { updateUnsavedChanges() } }
    @Published var expiryDate: Date = Date().addingTimeInterval(86400 * 30) { didSet { updateUnsavedChanges() } }
    
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
        condition = (acc.condition == .used) ? .used : .new
        
        if let exp = acc.expiryDate {
            hasExpiryDate = true
            expiryDate = exp
        }
        
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

    var screenTitle: String {
        if editingAccessory != nil {
            if isFood { return Language.get("Edit Food", alter: "تعديل الطعام") }
            if isLivePet { return Language.get("Edit Live Pet", alter: "تعديل الحيوان الأليف") }
            return Language.get("Edit Accessory", alter: "تعديل الإكسسوار")
        }
        if isFood { return Language.get("Add Food", alter: "إضافة طعام") }
        if isLivePet { return Language.get("Add Live Pet", alter: "إضافة حيوان أليف") }
        return Language.get("Add Accessory", alter: "إضافة إكسسوار")
    }

    var eyebrowKindText: String {
        if isFood { return Language.get("Food", alter: "طعام") }
        if isLivePet { return Language.get("Live pets", alter: "حيوانات حية") }
        return Language.get("Accessory", alter: "إكسسوار")
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
        accessory.quantity = max(0, quantity)
        
        accessory.condition = (isFood || condition == .new) ? .new : .used
        accessory.isNew = (accessory.condition != .used)
        accessory.accessKindType = selectedKind
        
        accessory.petMainCategoryID = selectedMainKind?.id ?? 0
        accessory.petSubCategoryID = selectedSubKind?.id ?? 0
        
        accessory.storeID = selectedStoreID.isEmpty ? "main_store" : selectedStoreID
        accessory.storeName = selectedStoreName.isEmpty ? Language.get("Main Store", alter: "المتجر الرئيسي") : selectedStoreName
        
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
                    : Language.get("Accessory has been created.", alter: "تمت إضافة المنتج بنجاح")
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.onDismiss()
                }
            }
        }
    }
}

// MARK: - Main SwiftUI Screen

@available(iOS 16.0, *)
struct PPAccessoryEditorScreen: View {
    @StateObject var viewModel: PPAccessoryEditorViewModel
    @FocusState private var focusedField: FormField?
    
    enum FormField: Hashable {
        case name, desc, price, discountPercent, discountAmount, quantity
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background
                .ignoresSafeArea()

            PPAdminForm {
                    dossierHeaderView
                    
                    if viewModel.showTypeRow && viewModel.editingAccessory == nil {
                        itemKindSelectorCard
                    }
                    
                    infoSectionCard
                    speciesAndBreedSectionCard
                    pricingSectionCard
                    inventorySectionCard
                    expiryDateSectionCard
                    storeSectionCard
                    imagesSectionCard
                    publishingSectionCard}
            .scrollDismissesKeyboard(.interactively)

            saveDockView
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
        .fullScreenCover(item: Binding(
            get: { viewModel.previewImageURL != nil ? ImagePreviewWrapper(url: viewModel.previewImageURL!) : (viewModel.previewUIImage != nil ? ImagePreviewWrapper(image: viewModel.previewUIImage!) : nil) },
            set: { _ in
                viewModel.previewImageURL = nil
                viewModel.previewUIImage = nil
            }
        )) { preview in
            PPAccessoryImageFullscreenViewer(
                imageURL: preview.url,
                uiImage: preview.image,
                onClose: {
                    viewModel.previewImageURL = nil
                    viewModel.previewUIImage = nil
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

    // MARK: - 1. Dossier Header

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if viewModel.hasUnsavedChanges {
                        viewModel.showDiscardConfirmation = true
                    } else {
                        viewModel.onDismiss()
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
                
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(AdminSurface.primary)
                }
            }

            Text(Language.get("CommandCenter_Inventory_Workspace", alter: "مساحة المخزون") + " / " + viewModel.eyebrowKindText)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(viewModel.screenTitle)
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let err = viewModel.errorMessage {
                AdminErrorBanner(message: err) {
                    viewModel.errorMessage = nil
                }
                .padding(.top, 4)
            } else if let kindsErr = viewModel.kindsErrorMessage {
                AdminErrorBanner(message: kindsErr) {
                    viewModel.loadMainKinds()
                }
                .padding(.top, 4)
            } else if let success = viewModel.saveSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(AdminType.calloutBold)
                        .foregroundColor(.green)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section Header Component

    private func sectionHeader(title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AdminSurface.primary)
                .frame(width: 3.5, height: 16)
            
            Text(title)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 2. Item Kind Selector

    private var itemKindSelectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: Language.get("Item Type", alter: "نوع العنصر"))
            
            HStack(spacing: 8) {
                kindOptionPill(kind: .typeAccessory, title: Language.get("Accessory", alter: "إكسسوار"), icon: "bag.fill")
                kindOptionPill(kind: .typeFood, title: Language.get("Food", alter: "طعام"), icon: "takeoutbag.and.cup.and.straw.fill")
                kindOptionPill(kind: .typeLivePets, title: Language.get("Live pets", alter: "حيوانات حية"), icon: "pawprint.fill")
            }
            .padding(6)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    private func kindOptionPill(kind: AccessKindType, title: String, icon: String) -> some View {
        let isSelected = viewModel.selectedKind == kind
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.selectedKind = kind
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(AdminType.subheadlineBold)
            }
            .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isSelected ? AdminSurface.primary : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Info Section (معلومة)

    private var infoSectionCard: some View {
        PPAdminFormSection(title: Language.get("Info", alter: "معلومة")) {
            PPAdminFormTextField(
                title: Language.get("Name", alter: "الاسم"),
                placeholder: Language.get("Enter name", alter: "أدخل الاسم"),
                text: $viewModel.name,
                fieldType: .name,
                focusedField: $focusedField,
                submitLabel: .next,
                onSubmit: { focusedField = .desc }
            )
            
            PPAdminFormDivider()
            
            PPAdminFormTextEditor(
                title: Language.get("Description", alter: "الوصف"),
                placeholder: Language.get("Enter description", alter: "أدخل الوصف"),
                text: $viewModel.desc,
                fieldType: .desc,
                focusedField: $focusedField
            )
        }
    }

    // MARK: - 4. Species & Breed Section (النوع)

    private var speciesAndBreedSectionCard: some View {
        PPAdminFormSection(title: Language.get("Species", alter: "النوع")) {
            PPAdminFormButtonRow(
                title: Language.get("Species", alter: "النوع"),
                value: viewModel.selectedMainKind?.kindName,
                placeholder: Language.get("SpeciesPlaceholder", alter: "اختر النوع"),
                icon: Language.isRTL() ? "chevron.left" : "chevron.right"
            ) {
                focusedField = nil
                viewModel.showSpeciesPicker = true
            }
            
            PPAdminFormDivider()
            
            PPAdminFormButtonRow(
                title: Language.get("Breed", alter: "السلالة"),
                value: viewModel.selectedSubKind?.subKindName,
                placeholder: Language.get("BreedPlaceholder", alter: "اختر السلالة"),
                icon: Language.isRTL() ? "chevron.left" : "chevron.right"
            ) {
                if viewModel.selectedMainKind != nil {
                    focusedField = nil
                    viewModel.showBreedPicker = true
                }
            }
        }
    }

    // MARK: - 5. Pricing Section (السعر)

    private var pricingSectionCard: some View {
        PPAdminFormSection(title: Language.get("Pricing", alter: "التسعير")) {
            PPAdminFormTextField(
                title: Language.get("Price", alter: "السعر"),
                placeholder: "0.00",
                text: $viewModel.priceText,
                isNumber: true,
                fieldType: .price,
                focusedField: $focusedField,
                suffix: Language.get("QAR", alter: "ر.ق")
            )
            
            PPAdminFormDivider()
            
            PPAdminFormTextField(
                title: Language.get("DiscountPercent", alter: "نسبة الخصم %"),
                placeholder: "0",
                text: $viewModel.discountPercentText,
                isNumber: true,
                fieldType: .discountPercent,
                focusedField: $focusedField,
                suffix: "%"
            )
            
            PPAdminFormDivider()
            
            PPAdminFormTextField(
                title: Language.get("DiscountAmount", alter: "مبلغ الخصم"),
                placeholder: "0.00",
                text: $viewModel.discountAmountText,
                isNumber: true,
                fieldType: .discountAmount,
                focusedField: $focusedField,
                suffix: Language.get("QAR", alter: "ر.ق")
            )
            
            // Final Calculated Price Card
            HStack {
                Text(Language.get("FinalPrice", alter: "السعر النهائي"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primary)
                
                Spacer()
                
                Text(viewModel.formattedFinalPrice)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(
                AdminSurface.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(10)
        }
    }

    // MARK: - 6. Inventory & Condition Section (المخزون)

    private var inventorySectionCard: some View {
        PPAdminFormSection(title: Language.get("StockSection", alter: "المخزون")) {
            PPAdminFormTextField(
                title: Language.get("Quantity", alter: "الكمية"),
                placeholder: "0",
                value: $viewModel.quantity,
                isNumber: true,
                fieldType: .quantity,
                focusedField: $focusedField
            )
            
            PPAdminFormDivider()
            
            // Condition Pill Row
            HStack {
                Text(Language.get("Condition", alter: "الحالة"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 100, alignment: .leading)
                
                HStack(spacing: 8) {
                    conditionPill(condition: .new, title: Language.get("New", alter: "جديد"))
                    conditionPill(condition: .used, title: Language.get("Used", alter: "مستعمل"))
                }
                .padding(6)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .padding(.vertical, 4)
        }
    }

    private func conditionPill(condition: AccessConditions, title: String) -> some View {
        let isSelected = viewModel.condition == condition
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.condition = condition
        }) {
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    isSelected ? AdminSurface.primary : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 7. Expiry Date Section (تاريخ الانتهاء)

    private var expiryDateSectionCard: some View {
        PPAdminFormSection(title: Language.get("Expiry Date", alter: "تاريخ الانتهاء")) {
            PPAdminFormToggle(
                title: Language.get("Has Expiry Date", alter: "يوجد تاريخ انتهاء"),
                isOn: $viewModel.hasExpiryDate
            )
            
            if viewModel.hasExpiryDate {
                PPAdminFormDivider()
                
                DatePicker(
                    Language.get("Select Date", alter: "اختر التاريخ"),
                    selection: $viewModel.expiryDate,
                    displayedComponents: .date
                )
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
                .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US"))
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
        }
    }

    // MARK: - 8. Store Section (المتجر)

    private var storeSectionCard: some View {
        PPAdminFormSection(title: Language.get("StoreSection", alter: "المتجر")) {
            PPAdminFormButtonRow(
                title: Language.get("Store", alter: "المتجر"),
                value: viewModel.selectedStoreName,
                placeholder: Language.get("SelectStorePlaceholder", alter: "اختر المتجر"),
                icon: Language.isRTL() ? "chevron.left" : "chevron.right"
            ) {
                focusedField = nil
                viewModel.showStorePicker = true
            }
        }
    }

    // MARK: - 9. Images Section (الصور)

    private var imagesSectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(title: Language.get("Images", alter: "الصور"))
                Spacer()
                Text("\(viewModel.totalImageCount)/9")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Add Button Opening Native PHPicker
                        if viewModel.canAddImages {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.showImagePicker = true
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20))
                                    Text(Language.get("Add", alter: "إضافة"))
                                        .font(AdminType.captionBold)
                                }
                                .foregroundColor(AdminSurface.primary)
                                .frame(width: 80, height: 80)
                                .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                        .foregroundColor(AdminSurface.primary.opacity(0.4))
                                )
                            }
                        }

                        // Existing Images
                        ForEach(Array(viewModel.existingImageURLs.enumerated()), id: \.offset) { index, urlString in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: URL(string: urlString)) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 80, height: 80)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .frame(width: 80, height: 80)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .background(AdminSurface.control)
                                .cornerRadius(12)
                                .onTapGesture {
                                    viewModel.previewImageURL = urlString
                                }

                                Button(action: {
                                    viewModel.removeExistingImage(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }

                        // Newly Picked Local Images
                        ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, uiImage in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .background(AdminSurface.control)
                                    .cornerRadius(12)
                                    .onTapGesture {
                                        viewModel.previewUIImage = uiImage
                                    }

                                Button(action: {
                                    viewModel.removePickedImage(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: - 10. Publishing & Draft Section (النشر)

    private var publishingSectionCard: some View {
        PPAdminFormSection(title: Language.get("Publishing Status", alter: "حالة النشر")) {
            PPAdminFormToggle(
                title: Language.get("Draft", alter: "مسودة"),
                subtitle: Language.get("DraftDesc", alter: "إخفاء عن المستخدمين"),
                isOn: $viewModel.isDraft
            )
        }
    }

    // MARK: - 11. Sticky Save Dock

    private var saveDockView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.isSubmitting {
                        Text(Language.get("Uploading", alter: "جارٍ الحفظ والرفع..."))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                    } else if viewModel.hasUnsavedChanges {
                        Text(Language.get("CommandCenter_UnsavedChanges", alter: "تغييرات غير محفوظة"))
                            .font(AdminType.captionBold)
                            .foregroundColor(.orange)
                    } else if viewModel.isDraft {
                        Text(Language.get("Draft", alter: "مسودة"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Text(Language.get("Ready to save", alter: "جاهز للحفظ"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Text(viewModel.formattedFinalPrice)
                        .font(AdminType.footnoteBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                Button(action: {
                    focusedField = nil
                    viewModel.saveAccessory()
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(viewModel.isSubmitting ? Language.get("Uploading", alter: "جارٍ الرفع...") : Language.get("Save", alter: "حفظ"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background(
                        viewModel.isSubmitting ? AdminSurface.primary.opacity(0.6) : AdminSurface.primary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .disabled(viewModel.isSubmitting)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 12)
            .background(AdminSurface.surface.opacity(0.95))
        }
    }
}

// MARK: - Native PHPickerViewController Representable (iOS 14.0+)

struct PPImagePickerSheet: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPickImages: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, maxSelection)
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

            var loadedImages: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                        if let img = image as? UIImage {
                            loadedImages.append(img)
                        }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                if !loadedImages.isEmpty {
                    self.parent.onPickImages(loadedImages)
                }
            }
        }
    }
}

// MARK: - Helper Modals & Pickers

@available(iOS 16.0, *)
struct PPAccessorySpeciesPickerSheet: View {
    let speciesList: [MainKindsModel]
    let selectedSpecies: MainKindsModel?
    let onSelect: (MainKindsModel) -> Void
    
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    var filteredList: [MainKindsModel] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return speciesList
        }
        return speciesList.filter {
            $0.kindName.localizedCaseInsensitiveContains(searchText) ||
            $0.kindNameAr.localizedCaseInsensitiveContains(searchText) ||
            $0.kindNameEn.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AdminSearchField(text: $searchText, placeholder: Language.get("Search species...", alter: "ابحث عن نوع..."))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                List(filteredList, id: \.id) { species in
                    Button(action: {
                        onSelect(species)
                    }) {
                        HStack {
                            Text(species.kindName)
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                            
                            Spacer()
                            
                            if selectedSpecies?.id == species.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .listRowBackground(AdminSurface.surface)
                }
                .listStyle(.plain)
                .hideScrollContentBackgroundIfPossible()
                .background(AdminSurface.background)
            }
            .navigationTitle(Language.get("Select Species", alter: "اختر النوع"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

@available(iOS 16.0, *)
struct PPAccessoryBreedPickerSheet: View {
    let breedList: [SubKindModel]
    let selectedBreed: SubKindModel?
    let onSelect: (SubKindModel?) -> Void
    
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    var filteredList: [SubKindModel] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return breedList
        }
        return breedList.filter {
            $0.subKindName.localizedCaseInsensitiveContains(searchText) ||
            $0.subKindNameAr.localizedCaseInsensitiveContains(searchText) ||
            $0.subKindNameEn.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AdminSearchField(text: $searchText, placeholder: Language.get("Search breed...", alter: "ابحث عن السلالة..."))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                List {
                    // Option to clear breed selection (Optional)
                    Button(action: {
                        onSelect(nil)
                    }) {
                        HStack {
                            Text(Language.get("No specific breed", alter: "بدون سلالة محددة (عام)"))
                                .font(AdminType.callout)
                                .foregroundColor(AdminSurface.secondaryText)
                            
                            Spacer()
                            
                            if selectedBreed == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .listRowBackground(AdminSurface.surface)

                    ForEach(filteredList, id: \.id) { breed in
                        Button(action: {
                            onSelect(breed)
                        }) {
                            HStack {
                                Text(breed.subKindName)
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                
                                Spacer()
                                
                                if selectedBreed?.id == breed.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AdminSurface.primary)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .listRowBackground(AdminSurface.surface)
                    }
                }
                .listStyle(.plain)
                .hideScrollContentBackgroundIfPossible()
                .background(AdminSurface.background)
            }
            .navigationTitle(Language.get("Select Breed", alter: "اختر السلالة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

@available(iOS 16.0, *)
@available(iOS 16.0, *)
struct PPAccessoryStorePickerSheet: View {
    let stores: [(id: String, name: String)]
    let selectedStoreID: String
    let onSelect: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(stores, id: \.id) { store in
                Button(action: {
                    onSelect(store.id, store.name)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name)
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(store.id)
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        
                        Spacer()
                        
                        if selectedStoreID == store.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                    .frame(minHeight: 48)
                }
                .listRowBackground(AdminSurface.surface)
            }
            .listStyle(.plain)
            .hideScrollContentBackgroundIfPossible()
            .background(AdminSurface.background)
            .navigationTitle(Language.get("Select Store", alter: "اختر المتجر"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct ImagePreviewWrapper: Identifiable {
    var id: String { url ?? UUID().uuidString }
    var url: String?
    var image: UIImage?
    
    init(url: String) { self.url = url; self.image = nil }
    init(image: UIImage) { self.url = nil; self.image = image }
}

struct PPAccessoryImageFullscreenViewer: View {
    let imageURL: String?
    let uiImage: UIImage?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else if let urlStr = imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6), in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - UIViewController Hosting Bridge for Objective-C & Swift Call Sites

@available(iOS 16.0, *)
@objc public final class PPAccessoryEditorHostingBridge: NSObject {
    @MainActor @objc public static func makeViewController(
        accessory: PetAccessory?,
        showTypeRow: Bool,
        defaultKind: AccessKindType,
        onDismiss: @escaping () -> Void
    ) -> UIViewController {
        let viewModel = PPAccessoryEditorViewModel(
            accessory: accessory,
            showTypeRow: showTypeRow,
            defaultKind: defaultKind,
            onDismiss: onDismiss
        )
        let swiftUIView = PPAccessoryEditorScreen(viewModel: viewModel)
        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = UIColor.ppBackground
        return host
    }
}

extension View {
    @ViewBuilder
    func hideScrollContentBackgroundIfPossible() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
import SwiftUI

// MARK: - Core Container

public struct PPAdminForm<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AdminSpacing.groupSpacing) {
                content
                
                Spacer().frame(height: 120) // Bottom dock clearance
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.sm)
        }
    }
}

// MARK: - Form Section

public struct PPAdminFormSection<Content: View>: View {
    let title: String
    let content: Content

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AdminSurface.primary)
                    .frame(width: 3.5, height: 16)
                
                Text(title)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.horizontal, 4)
            
            // Card Content
            VStack(spacing: 0) {
                content
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(AdminSurface.hairline)
            )
        }
    }
}

// MARK: - Form Divider (for between rows)

public struct PPAdminFormDivider: View {
    public init() {}
    public var body: some View {
        Divider()
            .background(AdminSurface.hairline)
            .padding(.horizontal, 16)
    }
}

// MARK: - Form TextField

public struct PPAdminFormTextField<F: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isNumber: Bool
    let alignment: TextAlignment
    let fieldType: F?
    let focusedField: FocusState<F?>.Binding
    let submitLabel: SubmitLabel
    let suffix: String?
    let onSubmit: (() -> Void)?

    public init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isNumber: Bool = false,
        alignment: TextAlignment = .leading,
        fieldType: F? = nil,
        focusedField: FocusState<F?>.Binding,
        submitLabel: SubmitLabel = .next,
        suffix: String? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isNumber = isNumber
        self.alignment = alignment
        self.fieldType = fieldType
        self.focusedField = focusedField
        self.submitLabel = submitLabel
        self.suffix = suffix
        self.onSubmit = onSubmit
    }
    
    public init(
        title: String,
        placeholder: String,
        value: Binding<Int>,
        isNumber: Bool = true,
        alignment: TextAlignment = .leading,
        fieldType: F? = nil,
        focusedField: FocusState<F?>.Binding,
        submitLabel: SubmitLabel = .next,
        suffix: String? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = Binding<String>(
            get: { String(value.wrappedValue) },
            set: { value.wrappedValue = Int($0) ?? 0 }
        )
        self.isNumber = isNumber
        self.alignment = alignment
        self.fieldType = fieldType
        self.focusedField = focusedField
        self.submitLabel = submitLabel
        self.suffix = suffix
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(width: 100, alignment: .leading)
            
            TextField(placeholder, text: $text)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(alignment)
                .keyboardType(isNumber ? .decimalPad : .default)
                .focused(focusedField, equals: fieldType)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
            
            if let suffix = suffix {
                Text(suffix)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

// MARK: - Form TextEditor

public struct PPAdminFormTextEditor<F: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat
    let fieldType: F?
    let focusedField: FocusState<F?>.Binding

    public init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 70,
        fieldType: F? = nil,
        focusedField: FocusState<F?>.Binding
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
        self.fieldType = fieldType
        self.focusedField = focusedField
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
            
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
                
                TextEditor(text: $text)
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(minHeight: minHeight)
                    .hideScrollContentBackgroundIfPossible()
                    .focused(focusedField, equals: fieldType)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Form Button Row (e.g. Navigation style or Picker)

public struct PPAdminFormButtonRow: View {
    let title: String
    let value: String?
    let placeholder: String
    let icon: String?
    let action: () -> Void

    public init(
        title: String,
        value: String? = nil,
        placeholder: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 100, alignment: .leading)
                
                Spacer()
                
                Text(value ?? placeholder)
                    .font(AdminType.callout)
                    .foregroundColor(value != nil ? AdminSurface.primaryText : AdminSurface.secondaryText)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form Toggle

public struct PPAdminFormToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    public init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        }
        .tint(AdminSurface.primary)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}
