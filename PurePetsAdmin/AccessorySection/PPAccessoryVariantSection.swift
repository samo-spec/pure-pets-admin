//
//  PPAccessoryVariantSection.swift
//  PurePetsAdmin
//
//  "Variants & Media" — the colour workspace inside the accessory editor.
//
//  Lives in its own file so the 19k-line editor takes a single small hook. Uses
//  the editor's existing tokens (AdminSurface / AdminType / AdminCommandInk) and
//  the shared AdminBarcodeScanButton rather than introducing a parallel design
//  system.
//
//  ── Ownership boundaries this screen respects ──────────────────────────────
//  • Colour identity, ordering, default selection and archive state are owned by
//    `upsertProductVariantFamily` and edited here.
//  • SKU, barcode, price, images and stock belong to each colour's own
//    `petAccessories` record and are owned by `validateInventoryChange` /
//    `upsertProductCommerce`. They are shown read-only with a route to the
//    colour's own product record, so this screen can never become a second
//    writer of them.
//  • Availability shown per colour is a live projection, never an authority.
//

import SwiftUI
import PhotosUI

// MARK: - SwiftUI colour bridge

extension PPAccessoryVariantColor {
    /// SwiftUI view of the swatch. The model exposes `uiColor` for the
    /// Objective-C surface; this keeps the SwiftUI call sites readable without
    /// putting a non-`@objc` type on the model.
    var uiColorValue: Color { Color(uiColor: uiColor) }
}

// MARK: - Predefined colour library

/// Starting palette. The operator can always define a custom colour; this only
/// removes the need to type a hex for the common cases. Identifiers are stable
/// and must never be renamed once a product has shipped with them.
enum PPAccessoryVariantColorLibrary {
    static let entries: [PPAccessoryVariantColor] = [
        .init(identifier: "black", nameAr: "أسود", nameEn: "Black", hex: "#111111"),
        .init(identifier: "white", nameAr: "أبيض", nameEn: "White", hex: "#FFFFFF"),
        .init(identifier: "grey", nameAr: "رمادي", nameEn: "Grey", hex: "#9E9E9E"),
        .init(identifier: "beige", nameAr: "بيج", nameEn: "Beige", hex: "#D7C4A3"),
        .init(identifier: "brown", nameAr: "بني", nameEn: "Brown", hex: "#6D4C41"),
        .init(identifier: "crimson-red", nameAr: "أحمر", nameEn: "Red", hex: "#D71920"),
        .init(identifier: "rose-pink", nameAr: "وردي", nameEn: "Pink", hex: "#EC6F9C"),
        .init(identifier: "amber-orange", nameAr: "برتقالي", nameEn: "Orange", hex: "#F08A24"),
        .init(identifier: "sun-yellow", nameAr: "أصفر", nameEn: "Yellow", hex: "#F6C445"),
        .init(identifier: "forest-green", nameAr: "أخضر", nameEn: "Green", hex: "#2E7D32"),
        .init(identifier: "teal", nameAr: "أزرق مخضر", nameEn: "Teal", hex: "#00897B"),
        .init(identifier: "ocean-blue", nameAr: "أزرق", nameEn: "Blue", hex: "#1B6CA8"),
        .init(identifier: "navy", nameAr: "كحلي", nameEn: "Navy", hex: "#1A237E"),
        .init(identifier: "violet", nameAr: "بنفسجي", nameEn: "Violet", hex: "#6A3AB2"),
    ]
}

// MARK: - Section model

@MainActor
final class PPAccessoryVariantSectionModel: ObservableObject {
    /// Baseline as loaded from the server; the comparison target for dirty state.
    @Published private(set) var baseline: PPAccessoryVariantFamily?
    /// Editable working copy.
    @Published var draft: PPAccessoryVariantFamily?
    @Published var selectedProductId: String = ""
    @Published private(set) var rootAccessory: PetAccessory?

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var validationMessages: [String] = []
    @Published var failure: PPAccessoryVariantFailureState? {
        didSet {
            if failure != nil { confirmation = nil }
        }
    }
    @Published var confirmation: String? {
        didSet {
            if confirmation != nil { failure = nil }
        }
    }

    // MARK: Per-colour media
    //
    // Staged per colour so switching colours never mixes one colour's pictures
    // into another's. Uploads are deferred until the media save, matching the
    // editor's existing discipline.
    @Published var stagedImages: [String: [PPAccessoryVariantStagedImage]] = [:]
    @Published var retainedImageURLs: [String: [String]] = [:]
    @Published private(set) var isSavingMedia = false
    @Published private(set) var isCreatingVariant = false
    private var originalImageURLs: [String: [String]] = [:]
    private var imageMetadataByURL: [String: [String: Any]] = [:]
    private var pendingMediaCommandId: [String: String] = [:]

    /// Retained so a `retrySameCommand` recovery reuses the exact key the server
    /// already bound, rather than minting a new one and risking a second effect.
    private var pendingCommandId: String?
    @Published private var pendingSaveDraft: PPAccessoryVariantFamily?
    var isEditingLocked: Bool { isSaving || isCreatingVariant || pendingSaveDraft != nil }
    /// Add Color uses two independent idempotent commands: catalog create first,
    /// then family attach. Retain both across retries so an ambiguous response
    /// can never duplicate a product or family effect.
    private var pendingVariantCreateCommandId: String?
    private var pendingVariantAttachCommandId: String?
    private var pendingVariantAttachDraft: PPAccessoryVariantFamily?
    private var pendingVariantCreationIntent: [String: String]?
    private var pendingCreatedVariantProduct: PetAccessory?

    var canManageVariants: Bool { PPAccessoryVariantService.shared.canManageVariants }

    var isDirty: Bool {
        guard let draft else { return false }
        return draft.hasChanges(comparedTo: baseline)
    }

    var selectedVariant: PPAccessoryVariant? {
        guard let draft, !selectedProductId.isEmpty else { return nil }
        return draft.variant(forProductId: selectedProductId)
    }

    /// True when the product has never been grouped, so the section should invite
    /// conversion rather than present a populated rail.
    var isLegacyUngrouped: Bool { draft?.isLegacySingleVariant ?? false }

    // MARK: Load

    func load(for accessory: PetAccessory) async {
        rootAccessory = accessory
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let family = try await PPAccessoryVariantService.shared.resolveFamily(for: accessory)
            apply(loaded: family)
        } catch {
            // Logged with the underlying error: the operator-facing message for a
            // non-contract failure is deliberately generic, which leaves nothing
            // to diagnose from. The family id is included because a read failure
            // here is almost always a missing family document or a rules denial
            // on `ProductFamilies`, and those are indistinguishable in the UI.
            let nsError = error as NSError
            print("[PPAccessoryVariantSection] resolveFamily failed"
                  + " product=\(accessory.accessoryID ?? "nil")"
                  + " family=\(accessory.productFamilyId ?? "<none>")"
                  + " domain=\(nsError.domain) code=\(nsError.code)"
                  + " error=\(error.localizedDescription)")
            failure = PPAccessoryVariantFailureState(error: error)
        }
    }

    func loadAccessory(forProductId productId: String) async throws -> PetAccessory {
        try await PPAccessoryVariantService.shared.loadProduct(productId: productId)
    }

    func reload() async {
        if let root = rootAccessory {
            await load(for: root)
        }
    }

    private func apply(loaded family: PPAccessoryVariantFamily) {
        family.autoBindMissingOptionSelections()
        baseline = family
        let workingDraft = family.copyForEditing()
        workingDraft.autoBindMissingOptionSelections()
        draft = workingDraft
        if selectedProductId.isEmpty || family.variant(forProductId: selectedProductId) == nil {
            selectedProductId = family.defaultVariantProductId.isEmpty
                ? (family.variants.first?.productId ?? "")
                : family.defaultVariantProductId
        }
        // Reset media state from the confirmed server view. Any staged upload is
        // already committed or discarded by this point.
        retainedImageURLs = [:]
        originalImageURLs = [:]
        stagedImages = [:]
        imageMetadataByURL = [:]
        for variant in family.variants {
            let urls = variant.media.compactMap { $0.isUploaded ? $0.remoteURL : nil }
            retainedImageURLs[variant.productId] = urls
            originalImageURLs[variant.productId] = urls
            for media in variant.media where media.isUploaded {
                imageMetadataByURL[media.remoteURL] = media.metadataPayload()
            }
        }
        validationMessages = []
    }

    // MARK: Media

    func images(forProductId productId: String) -> [String] {
        retainedImageURLs[productId] ?? []
    }

    func staged(forProductId productId: String) -> [PPAccessoryVariantStagedImage] {
        stagedImages[productId] ?? []
    }

    func totalImageCount(forProductId productId: String) -> Int {
        images(forProductId: productId).count + staged(forProductId: productId).count
    }

    func canAddImage(forProductId productId: String) -> Bool {
        totalImageCount(forProductId: productId) < PPAccessoryVariantMediaService.maxImagesPerVariant
    }

    func addImages(_ images: [UIImage], forProductId productId: String) {
        guard !images.isEmpty else { return }
        var current = stagedImages[productId] ?? []
        let room = PPAccessoryVariantMediaService.maxImagesPerVariant - totalImageCount(forProductId: productId)
        guard room > 0 else { return }
        current.append(contentsOf: images.prefix(room).map { PPAccessoryVariantStagedImage(image: $0) })
        stagedImages[productId] = current
    }

    func removeUploadedImage(at index: Int, forProductId productId: String) {
        guard var urls = retainedImageURLs[productId], urls.indices.contains(index) else { return }
        urls.remove(at: index)
        retainedImageURLs[productId] = urls
    }

    func removeStagedImage(id: UUID, forProductId productId: String) {
        guard var current = stagedImages[productId] else { return }
        // A staged image that already reached Storage leaves an unreferenced
        // object; it is cleaned up when media is next committed or discarded.
        current.removeAll { $0.id == id }
        stagedImages[productId] = current
    }

    /// Promotes an uploaded image to primary. Index 0 is what legacy consumer
    /// clients render, so this is the only thing that decides the cover.
    func makePrimaryImage(at index: Int, forProductId productId: String) {
        guard var urls = retainedImageURLs[productId], urls.indices.contains(index), index > 0 else { return }
        let url = urls.remove(at: index)
        urls.insert(url, at: 0)
        retainedImageURLs[productId] = urls
    }

    func moveUploadedImage(at index: Int, by offset: Int, forProductId productId: String) {
        guard var urls = retainedImageURLs[productId] else { return }
        let target = index + offset
        guard urls.indices.contains(index), urls.indices.contains(target) else { return }
        urls.swapAt(index, target)
        retainedImageURLs[productId] = urls
    }

    func hasMediaChanges(forProductId productId: String) -> Bool {
        let original = originalImageURLs[productId] ?? []
        let retained = retainedImageURLs[productId] ?? []
        return original != retained || !(stagedImages[productId] ?? []).isEmpty
    }

    /// Commits one colour's media.
    ///
    /// Uploads first, then writes the catalog document through
    /// `validateInventoryChange`, then deletes objects the confirmed state no
    /// longer references. A failed upload keeps the operator's selection and the
    /// URLs that already succeeded, so a retry never duplicates objects.
    func saveMedia(forProductId productId: String, expectedRevision: Int? = nil, color: PPAccessoryVariantColor? = nil) async {
        let variant = draft?.variant(forProductId: productId)
        guard let mediaColor = variant?.color ?? color,
              let revision = expectedRevision ?? variant?.revision else { return }
        isSavingMedia = true
        failure = nil
        confirmation = nil
        defer { isSavingMedia = false }

        let commandId = pendingMediaCommandId[productId] ?? "variant-media-\(productId)-\(UUID().uuidString)"
        pendingMediaCommandId[productId] = commandId

        var staged = stagedImages[productId] ?? []
        do {
            try await PPAccessoryVariantMediaService.shared.uploadStagedImages(
                &staged,
                productId: productId,
                colorId: mediaColor.identifier
            )
            // Retain whatever succeeded before attempting the catalog write.
            stagedImages[productId] = staged

            let commit = PPAccessoryVariantMediaService.shared.commit(
                productId: productId,
                retainedURLs: retainedImageURLs[productId] ?? [],
                staged: staged,
                previousURLs: originalImageURLs[productId] ?? [],
                metadataByURL: imageMetadataByURL
            )
            try await PPAccessoryVariantMediaService.shared.persist(
                commit,
                commandId: commandId,
                expectedRevision: revision
            )

            // Catalog state is confirmed, so unreferenced objects can go.
            await PPAccessoryVariantMediaService.shared.deleteOrphans(commit.orphanedURLs)

            pendingMediaCommandId[productId] = nil
            stagedImages[productId] = []
            retainedImageURLs[productId] = commit.imageURLs
            originalImageURLs[productId] = commit.imageURLs
            for entry in commit.imageMeta {
                if let url = entry["url"] as? String { imageMetadataByURL[url] = entry }
            }
            confirmation = Language.get("Variant_Media_Saved", alter: "تم حفظ صور اللون.")
        } catch let mediaError as PPAccessoryVariantMediaError {
            // Keep the staged selection so the operator does not re-pick.
            stagedImages[productId] = staged
            failure = PPAccessoryVariantFailureState(
                message: mediaError.errorDescription ?? "",
                recovery: .retrySameCommand
            )
        } catch {
            stagedImages[productId] = staged
            failure = PPAccessoryVariantFailureState(error: error)
            if !(failure?.allowsSameCommandRetry ?? false) { pendingMediaCommandId[productId] = nil }
        }
    }

    // MARK: Mutations

    func select(productId: String) {
        selectedProductId = productId
    }

    func updateColor(_ color: PPAccessoryVariantColor, forProductId productId: String) {
        guard let draft, let index = draft.variants.firstIndex(where: { $0.productId == productId }) else { return }
        let existing = draft.variants[index]
        var updatedOptions = existing.selectedOptions
        if let colorDef = draft.optionDefinitions.first(where: { $0.isColorOption }) {
            updatedOptions[colorDef.id] = color.identifier
        }
        updatedOptions[PPAccessoryVariantContract.axisColor] = color.identifier
        let updatedKey = PPAccessoryVariantFamily.combinationKey(from: updatedOptions)
        draft.variants[index] = PPAccessoryVariant(
            productId: existing.productId,
            color: color,
            sortOrder: existing.sortOrder,
            isArchived: existing.isArchived,
            isDefault: existing.isDefault,
            sku: existing.sku,
            barcode: existing.barcode,
            primaryImageURL: existing.primaryImageURL,
            quantity: existing.quantity,
            retailPrice: existing.retailPrice,
            wholesalePrice: existing.wholesalePrice,
            hasResolvedRetailPrice: existing.hasResolvedRetailPrice,
            showInAppMarket: existing.showInAppMarket,
            revision: existing.revision,
            media: existing.media,
            selectedOptions: updatedOptions,
            combinationKey: updatedKey
        )
        if draft.optionDefinitions.isEmpty {
            draft.optionDefinitions = [PPAccessoryOptionDefinition.synthesizeColorOption(fromVariants: draft.variants)]
        }
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    /// Converts a standalone single-variant product into a multi-option family using the chosen option definition
    /// (e.g. Size, Weight/Scale, Flavor, Material, or Custom) without requiring color first.
    func convertWithPresetOption(_ option: PPAccessoryOptionDefinition) {
        guard let draft else { return }
        draft.isLegacySingleVariant = false
        draft.optionDefinitions = [option]

        if let firstVariant = draft.variants.first {
            let initialColor = firstVariant.color.identifier.isEmpty
                ? PPAccessoryVariantColor.standardNeutral
                : firstVariant.color
            let defaultValId = option.values.first?.id ?? ""
            let updatedVariant = PPAccessoryVariant(
                productId: firstVariant.productId,
                color: initialColor,
                sortOrder: firstVariant.sortOrder,
                isArchived: firstVariant.isArchived,
                isDefault: true,
                sku: firstVariant.sku,
                barcode: firstVariant.barcode,
                primaryImageURL: firstVariant.primaryImageURL,
                quantity: firstVariant.quantity,
                retailPrice: firstVariant.retailPrice,
                wholesalePrice: firstVariant.wholesalePrice,
                hasResolvedRetailPrice: firstVariant.hasResolvedRetailPrice,
                showInAppMarket: firstVariant.showInAppMarket,
                revision: firstVariant.revision,
                media: firstVariant.media,
                selectedOptions: [option.id: defaultValId],
                combinationKey: "\(option.id)=\(defaultValId)"
            )
            draft.variants = [updatedVariant]
        }
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    func setDefault(productId: String) {
        guard let draft else { return }
        guard let target = draft.variant(forProductId: productId), !target.isArchived else { return }
        draft.defaultVariantProductId = productId
        for index in draft.variants.indices {
            draft.variants[index].isDefault = draft.variants[index].productId == productId
        }
        self.draft = draft
        revalidate()
    }

    func setArchived(_ archived: Bool, forProductId productId: String) {
        guard let draft, let index = draft.variants.firstIndex(where: { $0.productId == productId }) else { return }
        draft.variants[index].isArchived = archived
        // Archiving the default would leave the family without one, so hand the
        // default to the first remaining active colour instead of letting the
        // save fail later.
        if archived, draft.defaultVariantProductId == productId,
           let replacement = draft.variants.first(where: { !$0.isArchived }) {
            draft.defaultVariantProductId = replacement.productId
            for i in draft.variants.indices {
                draft.variants[i].isDefault = draft.variants[i].productId == replacement.productId
            }
        }
        self.draft = draft
        revalidate()
    }

    func toggleArchive(forProductId productId: String) {
        guard let current = draft?.variant(forProductId: productId) else { return }
        setArchived(!current.isArchived, forProductId: productId)
    }

    func move(productId: String, by offset: Int) {
        guard let draft, let index = draft.variants.firstIndex(where: { $0.productId == productId }) else { return }
        let target = index + offset
        guard draft.variants.indices.contains(target) else { return }
        draft.variants.swapAt(index, target)
        for (position, _) in draft.variants.enumerated() {
            draft.variants[position].sortOrder = position
        }
        self.draft = draft
        revalidate()
    }

    func removeVariant(productId: String) {
        guard let draft else { return }
        guard draft.variants.count > 1 else {
            failure = PPAccessoryVariantFailureState(
                message: Language.get("Variant_Error_CannotDeleteOnlyVariant", alter: "لا يمكن حذف المتغير الوحيد في المنتج."),
                recovery: .correctInput
            )
            return
        }
        guard let targetIndex = draft.variants.firstIndex(where: { $0.productId == productId }) else { return }
        let targetVariant = draft.variants[targetIndex]
        let isDefault = targetVariant.isDefault
        draft.variants.remove(at: targetIndex)
        for (pos, _) in draft.variants.enumerated() {
            draft.variants[pos].sortOrder = pos
        }
        if isDefault, let first = draft.variants.first {
            first.isDefault = true
            draft.defaultVariantProductId = first.productId
        }
        if selectedProductId == productId {
            selectedProductId = draft.variants.first?.productId ?? ""
        }
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        confirmation = Language.get("Variant_Delete_Confirmed", alter: "تم حذف المتغير من المجموعة بنجاح.")
        revalidate()
    }

    // MARK: - Options Mutations

    func addOption(_ option: PPAccessoryOptionDefinition) {
        guard let draft else { return }
        guard draft.optionDefinitions.count < PPAccessoryVariantContract.maxOptionsPerFamily else { return }
        guard !draft.optionDefinitions.contains(where: { $0.id == option.id || $0.key == option.key }) else { return }
        var updated = draft.optionDefinitions
        var newOption = option
        newOption.sortOrder = updated.count
        updated.append(newOption)
        draft.optionDefinitions = updated
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    func removeOption(withId id: String) {
        guard let draft else { return }
        if let message = draft.optionRemovalMessage(id: id) {
            failure = PPAccessoryVariantFailureState(message: message, recovery: .correctInput)
            return
        }
        var updated = draft.optionDefinitions
        updated.removeAll { $0.id == id }
        for (index, opt) in updated.enumerated() {
            opt.sortOrder = index
        }
        draft.optionDefinitions = updated
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    func moveOptionEarlier(id: String) {
        guard let draft else { return }
        guard let index = draft.optionDefinitions.firstIndex(where: { $0.id == id }), index > 0 else { return }
        var updated = draft.optionDefinitions
        updated.swapAt(index, index - 1)
        for (i, opt) in updated.enumerated() { opt.sortOrder = i }
        draft.optionDefinitions = updated
        self.draft = draft
        revalidate()
    }

    func moveOptionLater(id: String) {
        guard let draft else { return }
        guard let index = draft.optionDefinitions.firstIndex(where: { $0.id == id }), index < draft.optionDefinitions.count - 1 else { return }
        var updated = draft.optionDefinitions
        updated.swapAt(index, index + 1)
        for (i, opt) in updated.enumerated() { opt.sortOrder = i }
        draft.optionDefinitions = updated
        self.draft = draft
        revalidate()
    }

    func addOptionValue(_ value: PPAccessoryOptionValue, toOptionWithId optionId: String) {
        guard let draft else { return }
        guard let optIndex = draft.optionDefinitions.firstIndex(where: { $0.id == optionId }) else { return }
        let option = draft.optionDefinitions[optIndex]
        guard option.values.count < PPAccessoryVariantContract.maxValuesPerOption else { return }
        guard !option.values.contains(where: { $0.id == value.id || $0.canonicalValue.lowercased() == value.canonicalValue.lowercased() }) else { return }
        var updatedValues = option.values
        var newValue = value
        newValue.sortOrder = updatedValues.count
        updatedValues.append(newValue)
        option.values = updatedValues
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    func removeOptionValue(valueId: String, fromOptionWithId optionId: String) {
        guard let draft else { return }
        guard !isOptionValueInUse(valueId: valueId, optionId: optionId) else {
            failure = PPAccessoryVariantFailureState(message: Language.get("Options_Error_ValueInUse", alter: "هذه القيمة مرتبطة بصنف موجود. احتفظ بها، ويمكنك أرشفة الصنف من المصفوفة عند عدم الحاجة إليه."), recovery: .correctInput)
            return
        }
        guard let optIndex = draft.optionDefinitions.firstIndex(where: { $0.id == optionId }) else { return }
        let option = draft.optionDefinitions[optIndex]
        var updatedValues = option.values
        updatedValues.removeAll { $0.id == valueId }
        for (index, val) in updatedValues.enumerated() {
            val.sortOrder = index
        }
        option.values = updatedValues
        draft.autoBindMissingOptionSelections()
        self.draft = draft
        revalidate()
    }

    func moveOptionValueEarlier(valueId: String, inOptionWithId optionId: String) {
        guard let draft else { return }
        guard let optIndex = draft.optionDefinitions.firstIndex(where: { $0.id == optionId }) else { return }
        let option = draft.optionDefinitions[optIndex]
        guard let valIndex = option.values.firstIndex(where: { $0.id == valueId }), valIndex > 0 else { return }
        var updatedValues = option.values
        updatedValues.swapAt(valIndex, valIndex - 1)
        for (i, val) in updatedValues.enumerated() { val.sortOrder = i }
        option.values = updatedValues
        self.draft = draft
        revalidate()
    }

    func moveOptionValueLater(valueId: String, inOptionWithId optionId: String) {
        guard let draft else { return }
        guard let optIndex = draft.optionDefinitions.firstIndex(where: { $0.id == optionId }) else { return }
        let option = draft.optionDefinitions[optIndex]
        guard let valIndex = option.values.firstIndex(where: { $0.id == valueId }), valIndex < option.values.count - 1 else { return }
        var updatedValues = option.values
        updatedValues.swapAt(valIndex, valIndex + 1)
        for (i, val) in updatedValues.enumerated() { val.sortOrder = i }
        option.values = updatedValues
        self.draft = draft
        revalidate()
    }

    func isOptionValueInUse(valueId: String, optionId: String) -> Bool {
        guard let draft else { return false }
        for variant in draft.variants {
            if variant.selectedOptions[optionId] == valueId { return true }
            if optionId == PPAccessoryVariantContract.axisColor && variant.color.identifier == valueId { return true }
        }
        return false
    }

    /// Creates a standalone catalog record through the inventory command owner
    /// with initial quantity and images, then attaches the confirmed product to
    /// this family through the family owner. No direct Firestore catalog write occurs.
    func createAndAttachVariant(
        color: PPAccessoryVariantColor,
        selectedOptions: [String: String] = [:],
        sku: String,
        barcode: String,
        retailPrice: Double,
        wholesalePrice: Double?,
        quantity: Int = 0,
        images: [UIImage] = []
    ) async -> Bool {
        guard canManageVariants, !isSaving, !isCreatingVariant else { return false }
        // Persist newly added sizes/options before loading the family for the
        // attach transaction; otherwise the new combination references old data.
        if draft?.familyId.isEmpty == true || isDirty || pendingSaveDraft != nil {
            await save()
            guard failure == nil, !isDirty, pendingSaveDraft == nil,
                  let saved = draft, !saved.familyId.isEmpty else {
                if failure == nil, let message = validationMessages.first {
                    failure = PPAccessoryVariantFailureState(message: message, recovery: .correctInput)
                }
                return false
            }
        }
        guard let current = draft,
              !current.isLegacySingleVariant,
              !current.familyId.isEmpty else {
            failure = PPAccessoryVariantFailureState(
                message: Language.get(
                    "Variant_Add_SaveFamilyFirst",
                    alter: "احفظ لون المنتج الحالي أولاً، ثم أضف لوناً جديداً."
                ),
                recovery: .correctInput
            )
            return false
        }
        guard color.validationMessage == nil else {
            failure = PPAccessoryVariantFailureState(
                message: color.validationMessage ?? "",
                recovery: .correctInput
            )
            return false
        }
        if !current.hasGenericOptions && usedColorIdentifiers.contains(color.identifier) {
            failure = PPAccessoryVariantFailureState(
                message: Language.get("Variant_Error_ColorTaken", alter: "هذا اللون مستخدم بالفعل في هذا المنتج."),
                recovery: .correctInput
            )
            return false
        }
        var requestedOptions: [String: String] = [:]
        if current.hasGenericOptions {
            for option in current.optionDefinitions {
                let valueId = selectedOptions[option.id] ?? selectedOptions[option.key]
                    ?? (option.isColorOption ? color.identifier : "")
                guard option.values.contains(where: { $0.id == valueId }) else {
                    failure = PPAccessoryVariantFailureState(
                        message: Language.get("Options_Error_Incomplete", alter: "اختر قيمة لكل خيار قبل إنشاء المتغير."),
                        recovery: .correctInput
                    )
                    return false
                }
                requestedOptions[option.id] = valueId
            }
            let requestedKey = PPAccessoryVariantFamily.combinationKey(from: requestedOptions)
            if current.variants.contains(where: { PPAccessoryVariantFamily.combinationKey(from: $0.selectedOptions) == requestedKey }) {
                failure = PPAccessoryVariantFailureState(
                    message: Language.get("Variant_Error_CombinationTaken", alter: "هذه التوليفة مستخدمة بالفعل في هذا المنتج."),
                    recovery: .correctInput
                )
                return false
            }
        } else {
            requestedOptions[PPAccessoryVariantContract.axisColor] = color.identifier
        }
        guard retailPrice.isFinite, retailPrice > 0,
              wholesalePrice == nil || (wholesalePrice!.isFinite && wholesalePrice! > 0) else {
            failure = PPAccessoryVariantFailureState(
                message: Language.get("Variant_Add_InvalidPrice", alter: "أدخل سعر بيع صالحاً للون الجديد."),
                recovery: .correctInput
            )
            return false
        }

        let creationIntent = [
            "familyId": current.familyId,
            "selection": PPAccessoryVariantFamily.combinationKey(from: requestedOptions),
            "sku": sku.trimmingCharacters(in: .whitespacesAndNewlines),
            "barcode": barcode.trimmingCharacters(in: .whitespacesAndNewlines),
            "retailPrice": String(retailPrice),
            "wholesalePrice": wholesalePrice.map { String($0) } ?? "",
            "quantity": String(max(0, quantity))
        ]
        if let pendingVariantCreationIntent, pendingVariantCreationIntent != creationIntent {
            failure = PPAccessoryVariantFailureState(
                message: Language.get("Options_Create_Pending", alter: "هناك إنشاء متغير بانتظار التأكيد. أعد محاولة المتغير السابق بنفس بياناته قبل إنشاء متغير آخر."),
                recovery: .correctInput
            )
            return false
        }
        pendingVariantCreationIntent = creationIntent

        isCreatingVariant = true
        failure = nil
        confirmation = nil
        defer { isCreatingVariant = false }

        do {
            let product: PetAccessory
            if let pendingCreatedVariantProduct {
                product = pendingCreatedVariantProduct
            } else {
                guard let templateProductId = current.defaultVariantProductId.isEmpty
                    ? current.variants.first?.productId
                    : current.defaultVariantProductId else {
                    throw PPAccessoryVariantServiceError.invalidResponse
                }
                let template = try await PPAccessoryVariantService.shared.loadProduct(productId: templateProductId)
                let createCommandId = pendingVariantCreateCommandId
                    ?? "variant-product-create-\(current.familyId)-\(UUID().uuidString)"
                pendingVariantCreateCommandId = createCommandId
                product = try await PPAccessoryVariantService.shared.createStandaloneVariantProduct(
                    template: template,
                    sku: sku,
                    barcode: barcode,
                    retailPrice: retailPrice,
                    wholesalePrice: wholesalePrice,
                    quantity: max(0, quantity),
                    commandId: createCommandId
                )
                pendingCreatedVariantProduct = product
            }

            // Upload media for new product if photos were provided
            if !images.isEmpty, originalImageURLs[product.accessoryID] == nil {
                if staged(forProductId: product.accessoryID).isEmpty {
                    addImages(images, forProductId: product.accessoryID)
                }
                await saveMedia(forProductId: product.accessoryID, expectedRevision: product.revision, color: color)
                guard failure == nil else { return false }
            }

            // Reload before attaching so a concurrent family edit is merged into
            // the operator's intent instead of being overwritten by a stale draft.
            let latest = try await PPAccessoryVariantService.shared.loadFamily(familyId: current.familyId)
            if latest.variant(forProductId: product.accessoryID) != nil {
                apply(loaded: latest)
                clearPendingVariantCreation()
                confirmation = Language.get("Variant_Add_Confirmed", alter: "تمت إضافة اللون وحفظه.")
                return true
            }

            var finalOptions = requestedOptions
            if let colorDef = latest.optionDefinitions.first(where: { $0.isColorOption }) {
                finalOptions[colorDef.id] = color.identifier
            }
            if !latest.hasGenericOptions { finalOptions[PPAccessoryVariantContract.axisColor] = color.identifier }
            let combinationKey = PPAccessoryVariantFamily.combinationKey(from: finalOptions)

            if latest.hasGenericOptions {
                if latest.variants.contains(where: { $0.combinationKey == combinationKey }) {
                    throw PPAccessoryVariantServiceError.validationFailed([
                        Language.get("Variant_Error_CombinationTaken", alter: "هذه التوليفة مستخدمة بالفعل في هذا المنتج.")
                    ])
                }
            } else if latest.variants.contains(where: { $0.color.identifier == color.identifier }) {
                throw PPAccessoryVariantServiceError.validationFailed([
                    Language.get("Variant_Error_ColorTaken", alter: "هذا اللون مستخدم بالفعل في هذا المنتج.")
                ])
            }

            let refreshedProduct = try await PPAccessoryVariantService.shared.loadProduct(productId: product.accessoryID)
            let nextSort = (latest.variants.map(\.sortOrder).max() ?? -1) + 1
            latest.variants.append(PPAccessoryVariant(
                productId: refreshedProduct.accessoryID,
                color: color,
                sortOrder: nextSort,
                isArchived: false,
                isDefault: latest.variants.isEmpty,
                sku: refreshedProduct.sku ?? "",
                barcode: refreshedProduct.barcode ?? "",
                primaryImageURL: PetAccessory.firstImageURL(for: refreshedProduct)?.absoluteString ?? "",
                quantity: refreshedProduct.quantity,
                retailPrice: refreshedProduct.hasResolvedSellingPrice ? refreshedProduct.finalPrice : nil,
                wholesalePrice: refreshedProduct.wholesalePrice,
                hasResolvedRetailPrice: refreshedProduct.hasResolvedSellingPrice,
                showInAppMarket: false,
                revision: refreshedProduct.revision,
                media: (refreshedProduct.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) },
                selectedOptions: finalOptions,
                combinationKey: combinationKey
            ))
            latest.autoBindMissingOptionSelections()

            let attachCommandId = pendingVariantAttachCommandId
                ?? "variant-family-attach-\(current.familyId)-\(UUID().uuidString)"
            pendingVariantAttachCommandId = attachCommandId
            let attachDraft = pendingVariantAttachDraft ?? latest.copyForEditing()
            pendingVariantAttachDraft = attachDraft
            let attached = try await PPAccessoryVariantService.shared.saveFamily(attachDraft, commandId: attachCommandId)
            do {
                let reloaded = try await PPAccessoryVariantService.shared.loadFamily(familyId: current.familyId, minimumRevision: attached.revision)
                guard reloaded.variant(forProductId: refreshedProduct.accessoryID) != nil else {
                    throw PPAccessoryVariantServiceError.invalidResponse
                }
                apply(loaded: reloaded)
            } catch {
                failure = PPAccessoryVariantFailureState(message: Language.get("Options_Save_AwaitingReadback", alter: "استلم الخادم الحفظ، وتعذر تأكيد البيانات المحدثة. أعد المحاولة للتحقق من نفس العملية."), recovery: .retrySameCommand)
                return false
            }
            selectedProductId = refreshedProduct.accessoryID
            clearPendingVariantCreation()
            confirmation = Language.get("Variant_Add_Confirmed", alter: "تمت إضافة اللون وحفظه.")
            return true
        } catch {
            let state = PPAccessoryVariantFailureState(error: error)
            failure = state
            if !state.allowsSameCommandRetry {
                pendingVariantAttachCommandId = nil
                pendingVariantAttachDraft = nil
                if pendingCreatedVariantProduct == nil {
                    pendingVariantCreateCommandId = nil
                    pendingVariantCreationIntent = nil
                }
            }
            return false
        }
    }

    /// Matrix creation uses the same ordered save and retry path as the studio.
    func createAndAttachCombinationVariant(
        selectedOptions: [String: String],
        color: PPAccessoryVariantColor?,
        sku: String,
        barcode: String,
        retailPrice: Double,
        wholesalePrice: Double?,
        quantity: Int = 0,
        images: [UIImage] = []
    ) async -> Bool {
        let resolvedColor = color ?? PPAccessoryVariantColor(
            identifier: selectedOptions["color"] ?? "standard",
            nameAr: "افتراضي",
            nameEn: "Standard",
            hex: "#7F7F7F"
        )
        return await createAndAttachVariant(
            color: resolvedColor, selectedOptions: selectedOptions,
            sku: sku, barcode: barcode, retailPrice: retailPrice,
            wholesalePrice: wholesalePrice, quantity: quantity, images: images
        )
    }

    /// Applies bulk prices to multiple member variants through audited command facades.
    func applyBulkPricing(
        retailPrice: Double,
        wholesalePrice: Double?,
        forProductIds productIds: [String]
    ) async -> Bool {
        guard !productIds.isEmpty else { return false }
        isSaving = true
        failure = nil
        confirmation = nil
        defer { isSaving = false }

        var successCount = 0
        for productId in productIds {
            do {
                let product = try await PPAccessoryVariantService.shared.loadProduct(productId: productId)
                product.price = NSNumber(value: retailPrice)
                product.wholesalePrice = wholesalePrice.map { NSNumber(value: $0) }
                let retailMinor = Int((retailPrice * 100.0).rounded())
                let wholesaleMinor = wholesalePrice.map { Int(($0 * 100.0).rounded()) }

                var singleGroup: [String: Any] = [
                    "id": "single",
                    "nameAr": "حبة",
                    "nameEn": "Single",
                    "unitsPerGroup": 1,
                    "barcode": product.barcode?.isEmpty == false ? product.barcode! : NSNull(),
                    "sku": product.sku?.isEmpty == false ? product.sku! : NSNull(),
                    "sortOrder": 0,
                    "retailEnabled": true,
                    "wholesaleEnabled": wholesaleMinor != nil,
                    "retailPriceMinor": retailMinor,
                    "wholesalePriceMinor": wholesaleMinor ?? NSNull(),
                    "defaultForRetail": true,
                    "defaultForWholesale": wholesaleMinor != nil,
                    "active": true,
                ]
                if wholesaleMinor == nil { singleGroup["wholesalePriceMinor"] = NSNull() }
                let commerce: [String: Any] = [
                    "currency": "QAR",
                    "baseUnit": ["id": "piece", "nameAr": "قطعة", "nameEn": "Piece"],
                    "quantityGroups": [singleGroup],
                ]
                let branchId = (product.branchID ?? product.storeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let commandId = "bulk-price-\(productId)-\(UUID().uuidString)"
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PPInventoryCommandResult, Error>) in
                    PPInventoryCommandService.shared.saveProduct(
                        accessory: product,
                        branchId: branchId.isEmpty ? nil : branchId,
                        commerce: commerce,
                        expectedRevision: product.revision > 0 ? product.revision : nil,
                        commandId: commandId
                    ) { result, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let result, result.success { continuation.resume(returning: result) }
                        else { continuation.resume(throwing: PPAccessoryVariantServiceError.invalidResponse) }
                    }
                }
                successCount += 1
            } catch {
                print("[PPAccessoryVariantSection] bulk pricing failed for \(productId): \(error)")
            }
        }

        if let familyId = draft?.familyId, !familyId.isEmpty {
            if let reloaded = try? await PPAccessoryVariantService.shared.loadFamily(familyId: familyId) {
                apply(loaded: reloaded)
            }
        }
        confirmation = Language.get("Variant_BulkPricing_Success", alter: "تم تحديث أسعار المتغيرات بنجاح.")
        return successCount > 0
    }

    /// Updates an existing variant's color, pricing, quantity, SKU, barcode, and photos.
    /// Uses audited callable facades exclusively without direct Firestore writes.
    func updateVariant(
        productId: String,
        color: PPAccessoryVariantColor,
        selectedOptions: [String: String]? = nil,
        sku: String,
        barcode: String,
        retailPrice: Double,
        wholesalePrice: Double?,
        quantity: Int,
        newImages: [UIImage] = [],
        retainedURLs: [String]? = nil
    ) async -> Bool {
        guard draft != nil, !isEditingLocked else { return false }
        isSaving = true
        failure = nil
        confirmation = nil
        defer { isSaving = false }

        do {
            // 1. Update color and selected options in family draft
            updateColor(color, forProductId: productId)
            if let selectedOptions, let currentDraft = draft, let idx = currentDraft.variants.firstIndex(where: { $0.productId == productId }) {
                var opts = selectedOptions
                if let colorDef = currentDraft.optionDefinitions.first(where: { $0.isColorOption }) {
                    opts[colorDef.id] = color.identifier
                }
                opts[PPAccessoryVariantContract.axisColor] = color.identifier
                currentDraft.variants[idx].selectedOptions = opts
                currentDraft.variants[idx].combinationKey = PPAccessoryVariantFamily.combinationKey(from: opts)
                currentDraft.autoBindMissingOptionSelections()
                self.draft = currentDraft
            }

            revalidate()
            guard validationMessages.isEmpty else {
                failure = PPAccessoryVariantFailureState(message: validationMessages[0], recovery: .correctInput)
                return false
            }

            // 2. Load underlying product and apply catalog updates
            let product = try await PPAccessoryVariantService.shared.loadProduct(productId: productId)
            product.sku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
            product.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
            product.price = NSNumber(value: retailPrice)
            product.wholesalePrice = wholesalePrice.map { NSNumber(value: $0) }
            product.quantity = max(0, quantity)
            product.noStock = (quantity <= 0)

            let retailMinor = Int((retailPrice * 100.0).rounded())
            let wholesaleMinor = wholesalePrice.map { Int(($0 * 100.0).rounded()) }
            var singleGroup: [String: Any] = [
                "id": "single",
                "nameAr": "حبة",
                "nameEn": "Single",
                "unitsPerGroup": 1,
                "barcode": product.barcode?.isEmpty == false ? product.barcode! : NSNull(),
                "sku": product.sku?.isEmpty == false ? product.sku! : NSNull(),
                "sortOrder": 0,
                "retailEnabled": true,
                "wholesaleEnabled": wholesaleMinor != nil,
                "retailPriceMinor": retailMinor,
                "wholesalePriceMinor": wholesaleMinor ?? NSNull(),
                "defaultForRetail": true,
                "defaultForWholesale": wholesaleMinor != nil,
                "active": true,
            ]
            if wholesaleMinor == nil { singleGroup["wholesalePriceMinor"] = NSNull() }
            let commerce: [String: Any] = [
                "currency": "QAR",
                "baseUnit": ["id": "piece", "nameAr": "قطعة", "nameEn": "Piece"],
                "quantityGroups": [singleGroup],
            ]

            let branchId = (product.branchID ?? product.storeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let updateCommandId = "variant-product-update-\(productId)-\(UUID().uuidString)"
            let saveResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PPInventoryCommandResult, Error>) in
                PPInventoryCommandService.shared.saveProduct(
                    accessory: product,
                    branchId: branchId.isEmpty ? nil : branchId,
                    commerce: commerce,
                    expectedRevision: product.revision > 0 ? product.revision : nil,
                    commandId: updateCommandId
                ) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result, result.success {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: PPAccessoryVariantServiceError.invalidResponse)
                    }
                }
            }

            // 3. Update media if requested
            if let retainedURLs {
                retainedImageURLs[productId] = retainedURLs
            }
            if !newImages.isEmpty {
                addImages(newImages, forProductId: productId)
            }
            if hasMediaChanges(forProductId: productId) {
                await saveMedia(forProductId: productId, expectedRevision: saveResult.revision)
                guard failure == nil else { return false }
            }

            // Our own catalog/media write advanced this member's revision.
            // Use authoritative readback before the subsequent family command.
            let confirmedProduct = try await PPAccessoryVariantService.shared.loadProduct(productId: productId)
            guard confirmedProduct.revision >= saveResult.revision,
                  let pendingDraft = draft,
                  let index = pendingDraft.variants.firstIndex(where: { $0.productId == productId }) else {
                throw PPAccessoryVariantServiceError.invalidResponse
            }
            pendingDraft.variants[index] = pendingDraft.variants[index].refreshingCatalog(from: confirmedProduct)
            self.draft = pendingDraft

            // 4. Save family to sync color and variant ordering/attributes
            await save()
            guard failure == nil, pendingSaveDraft == nil, !isDirty else { return false }
            selectedProductId = productId
            confirmation = Language.get("Variant_Studio_UpdateSuccess", alter: "تم حفظ وتحديث اللون بنجاح.")
            return true
        } catch {
            failure = PPAccessoryVariantFailureState(error: error)
            return false
        }
    }

    private func clearPendingVariantCreation() {
        pendingVariantCreateCommandId = nil
        pendingVariantAttachCommandId = nil
        pendingVariantAttachDraft = nil
        pendingVariantCreationIntent = nil
        pendingCreatedVariantProduct = nil
    }

    /// Colours already used, so the picker can prevent a duplicate rather than
    /// letting the server reject it.
    var usedColorIdentifiers: Set<String> {
        Set((draft?.variants ?? []).map(\.color.identifier).filter { !$0.isEmpty })
    }

    func revalidate() {
        draft?.autoBindMissingOptionSelections()
        var messages = draft?.validationMessages() ?? []
        if let message = draft?.identityChangeMessage(comparedTo: baseline) { messages.append(message) }
        var seen = Set<String>()
        validationMessages = messages.filter { seen.insert($0).inserted }
        if failure?.recovery == .correctInput { failure = nil }
        if isDirty { confirmation = nil }
    }

    func showsAssignments(for option: PPAccessoryOptionDefinition) -> Bool {
        guard let draft else { return false }
        let isNewDimension = baseline?.optionDefinitions.contains(where: { $0.id == option.id }) != true
        return isNewDimension || draft.variants.contains { variant in
            !option.values.contains { $0.id == variant.selectedOptions[option.id] }
        }
    }

    func selectOptionValue(_ valueId: String, optionId: String, productId: String) {
        guard canManageVariants, !isEditingLocked, let draft,
              let definition = draft.optionDefinitions.first(where: { $0.id == optionId }),
              definition.values.contains(where: { $0.id == valueId }),
              let variant = draft.variant(forProductId: productId) else { return }
        if let baseline, !baseline.familyId.isEmpty,
           baseline.optionDefinitions.contains(where: { $0.id == optionId }),
           let previous = baseline.variant(forProductId: productId)?.selectedOptions[optionId], previous != valueId {
            failure = PPAccessoryVariantFailureState(message: Language.get("Options_Error_IdentityImmutable", alter: "لا يمكن تغيير قيمة خيار محفوظ لصنف موجود. أنشئ متغيرًا جديدًا للتوليفة الجديدة للحفاظ على المخزون والسجل."), recovery: .correctInput)
            return
        }
        variant.selectedOptions[optionId] = valueId
        variant.combinationKey = PPAccessoryVariantFamily.combinationKey(from: variant.selectedOptions)
        self.draft = draft
        revalidate()
    }

    func discardChanges() {
        guard !isEditingLocked else { return }
        guard let baseline else { return }
        draft = baseline.copyForEditing()
        draft?.autoBindMissingOptionSelections()
        validationMessages = []
        failure = nil
    }

    // MARK: Save

    func save() async {
        guard let workingDraft = pendingSaveDraft ?? draft else { return }
        if pendingSaveDraft == nil {
            workingDraft.autoBindMissingOptionSelections()
            revalidate()
            guard validationMessages.isEmpty else { return }
        }
        let draft = workingDraft.copyForEditing()

        isSaving = true
        failure = nil
        confirmation = nil
        defer { isSaving = false }

        let commandId = pendingCommandId ?? "variant-family-\(UUID().uuidString)"
        pendingCommandId = commandId
        pendingSaveDraft = draft

        do {
            let result = try await PPAccessoryVariantService.shared.saveFamily(
                draft,
                commandId: commandId
            )
            // Acceptance is not authoritative readback. Retain the exact draft
            // and command through ambiguity; never invent catalog revisions.
            do {
                let reloaded = try await PPAccessoryVariantService.shared.loadFamily(familyId: result.familyId, minimumRevision: result.revision)
                apply(loaded: reloaded)
                pendingCommandId = nil
                pendingSaveDraft = nil
                failure = nil
                confirmation = result.idempotent
                    ? Language.get("Variant_Save_AlreadyApplied", alter: "كانت هذه التغييرات محفوظة بالفعل.")
                    : Language.get("Options_Save_Confirmed", alter: "تم حفظ خيارات ومتغيرات المنتج.")
            } catch {
                confirmation = nil
                failure = PPAccessoryVariantFailureState(message: Language.get("Options_Save_AwaitingReadback", alter: "استلم الخادم الحفظ، وتعذر تأكيد البيانات المحدثة. أعد المحاولة للتحقق من نفس العملية."), recovery: .retrySameCommand)
            }
        } catch {
            confirmation = nil
            let state = PPAccessoryVariantFailureState(error: error)
            // Only a same-command retry may reuse the key. Any other outcome
            // must not reuse it: the server may already have bound it.
            if !state.allowsSameCommandRetry {
                pendingCommandId = nil
                pendingSaveDraft = nil
            }
            failure = state
            if !state.validationMessages.isEmpty { validationMessages = state.validationMessages }
        }
    }

    /// Reload used by the `reloadAndCompare` recovery. The draft is deliberately
    /// preserved so the operator can see what they had before deciding.
    func reloadFromServer() async {
        if let familyId = baseline?.familyId, !familyId.isEmpty {
            isLoading = true
            defer { isLoading = false }
            do {
                let reloaded = try await PPAccessoryVariantService.shared.loadFamily(familyId: familyId)
                baseline = reloaded
                failure = nil
                revalidate()
            } catch {
                failure = PPAccessoryVariantFailureState(error: error)
            }
        } else if let root = rootAccessory {
            await load(for: root)
        }
    }
}

// MARK: - Failure state

/// UI-facing projection of a failure, carrying the recovery intent so the view
/// never has to interpret an error itself.
struct PPAccessoryVariantFailureState {
    let message: String
    let recovery: PPAccessoryVariantRecovery
    let affectedProductIds: [String]
    let validationMessages: [String]

    init(error: Error) {
        if let serviceError = error as? PPAccessoryVariantServiceError {
            message = serviceError.errorDescription ?? ""
            recovery = serviceError.recovery
            validationMessages = serviceError.validationMessages
            if case .server(let typed) = serviceError {
                affectedProductIds = typed.affectedProductIds
            } else {
                affectedProductIds = []
            }
            return
        }
        let typed = PPAccessoryVariantError.error(from: error as NSError)
        message = typed.message
        recovery = typed.recovery
        affectedProductIds = typed.affectedProductIds
        validationMessages = []
    }

    /// Direct construction, for a failure that is already interpreted (media
    /// upload, for example) and does not need to go through the callable mapper.
    init(message: String, recovery: PPAccessoryVariantRecovery) {
        self.message = message
        self.recovery = recovery
        self.affectedProductIds = []
        self.validationMessages = []
    }

    var allowsSameCommandRetry: Bool { recovery == .retrySameCommand }

    /// Draft is preserved for every recovery except a fatal one.
    var preservesDraft: Bool { recovery != .fatal }

    var actionTitle: String? {
        switch recovery {
        case .correctInput:
            return nil
        case .reloadAndCompare:
            return Language.get("Variant_Recovery_Reload", alter: "إعادة التحميل والمقارنة")
        case .retrySameCommand:
            return Language.get("Variant_Recovery_Retry", alter: "إعادة المحاولة")
        case .transferPublicListingFirst:
            return Language.get("Variant_Recovery_TransferListing", alter: "نقل العرض ثم الحفظ")
        case .treatAsApplied:
            return Language.get("Variant_Recovery_Refresh", alter: "تحديث للتحقق")
        case .permissionDenied, .fatal:
            return nil
        }
    }

    var iconName: String {
        switch recovery {
        case .correctInput: return "exclamationmark.triangle.fill"
        case .reloadAndCompare: return "arrow.triangle.2.circlepath"
        case .retrySameCommand: return "arrow.clockwise"
        case .transferPublicListingFirst: return "arrow.left.arrow.right"
        case .treatAsApplied: return "checkmark.seal"
        case .permissionDenied: return "lock.fill"
        case .fatal: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch recovery {
        case .treatAsApplied: return AdminSurface.emerald
        case .permissionDenied, .fatal: return AdminSurface.crimson
        default: return AdminSurface.amber
        }
    }
}

// MARK: - Studio Segmented Switch

struct PPVariantSegmentedSwitch: View {
    @Binding var selectedTab: PPAccessoryVariantSection.VariantSectionTab
    let draft: PPAccessoryVariantFamily
    @Namespace private var switchNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PPAccessoryVariantSection.VariantSectionTab.allCases) { tab in
                let isSelected = (selectedTab == tab)
                Button {
                    guard selectedTab != tab else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    if reduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)

                        Text(tab.localizedTitle)
                            .font(isSelected ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                            .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)

                        // Micro Count Badge
                        let count = badgeCount(for: tab)
                        Text("\(count)")
                            .font(PPBrandFont.bold(size: 10.5))
                            .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AdminSurface.primary.opacity(0.12) : AdminSurface.container)
                            )
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PPVariantTabPressButtonStyle())
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AdminSurface.surface)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                            )
                            .matchedGeometryEffect(id: "STUDIO_TAB_ACTIVE_THUMB", in: switchNamespace)
                    }
                }
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityLabel(tabAccessibilityLabel(for: tab, isSelected: isSelected))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.5)
        )
    }

    private func tabIcon(for tab: PPAccessoryVariantSection.VariantSectionTab) -> String {
        switch tab {
        case .options:
            return "slider.horizontal.2.square.on.square"
        case .variants:
            return "paintpalette.fill"
        }
    }

    private func badgeCount(for tab: PPAccessoryVariantSection.VariantSectionTab) -> Int {
        switch tab {
        case .options:
            return draft.optionDefinitions.count
        case .variants:
            return draft.activeVariantCount
        }
    }

    private func tabAccessibilityLabel(for tab: PPAccessoryVariantSection.VariantSectionTab, isSelected: Bool) -> String {
        let count = badgeCount(for: tab)
        let selectedState = isSelected ? Language.get("Common_Selected", alter: "محدد") : ""
        return "\(tab.localizedTitle), \(count), \(selectedState)"
    }
}

fileprivate struct PPVariantTabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Category-Defining Presentation Mode Switch (Studio vs. Matrix)

struct PPVariantPresentationModeSwitch: View {
    @Binding var presentationMode: PPAccessoryVariantSection.VariantPresentationMode
    let draft: PPAccessoryVariantFamily
    let selectedVariant: PPAccessoryVariant?
    @Namespace private var modeNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                ForEach(PPAccessoryVariantSection.VariantPresentationMode.allCases) { mode in
                    let isSelected = (presentationMode == mode)
                    Button {
                        guard presentationMode != mode else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        if reduceMotion {
                            presentationMode = mode
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                                presentationMode = mode
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: modeIcon(for: mode))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)

                            Text(mode.localizedTitle)
                                .font(isSelected ? PPBrandFont.bold(size: 13.5) : PPBrandFont.medium(size: 13))
                                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            // Dynamic context micro-badge
                            switch mode {
                            case .atelier:
                                if let variant = selectedVariant {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(uiColor: variant.color.uiColor))
                                            .frame(width: 9, height: 9)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        variant.color.requiresContrastBorder ? Color.black.opacity(0.2) : Color.white.opacity(0.8),
                                                        lineWidth: 0.8
                                                    )
                                            )
                                        Text(variant.color.localizedName)
                                            .font(PPBrandFont.bold(size: 10))
                                            .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface)
                                    )
                                }
                            case .matrix:
                                Text("\(draft.variants.count)")
                                    .font(PPBrandFont.bold(size: 10))
                                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface)
                                    )
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PPVariantTabPressButtonStyle())
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AdminSurface.surface)
                                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                                )
                                .matchedGeometryEffect(id: "PRESENTATION_MODE_THUMB", in: modeNamespace)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityLabel(mode.localizedTitle)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.5)
            )

            // Dynamic Informative Micro-Caption
            HStack(spacing: 5) {
                Image(systemName: presentationMode == .atelier ? "sparkles" : "tablecells.badge.ellipsis")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(presentationMode == .atelier
                    ? Language.get("Variant_Mode_Atelier_Hint", alter: "تعديل تفصيلي للصور والباركود ومخزون المتغير المحدد")
                    : Language.get("Variant_Mode_Matrix_Hint", alter: "جدول شبكي موحد للتسعير الجماعي وتتبع كافة المتغيرات"))
                    .font(PPBrandFont.medium(size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .animation(.easeInOut(duration: 0.20), value: presentationMode)
        }
    }

    private func modeIcon(for mode: PPAccessoryVariantSection.VariantPresentationMode) -> String {
        switch mode {
        case .atelier:
            return "paintpalette.fill"
        case .matrix:
            return "tablecells.fill"
        }
    }
}

// MARK: - Section view

struct PPAccessoryVariantSection: View {
    @ObservedObject var model: PPAccessoryVariantSectionModel
    @ObservedObject private var branchPricing = PPBranchInventoryService.shared
    /// Invoked when the operator asks to open a colour's own product record,
    /// where SKU, barcode, price, stock and images are edited.
    var onOpenVariantProduct: ((String) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum VariantSectionTab: String, CaseIterable, Identifiable {
        case options
        case variants

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .options:
                return Language.get("Options_Tab_Options", alter: "الخيارات")
            case .variants:
                return Language.get("Options_Tab_Variants_Matrix", alter: "المصفوفة والمتغيرات")
            }
        }
    }

    enum VariantPresentationMode: String, CaseIterable, Identifiable {
        case matrix
        case atelier

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .matrix:
                return Language.get("Variant_Mode_Matrix", alter: "المصفوفة")
            case .atelier:
                return Language.get("Variant_Mode_Atelier", alter: "الاستوديو")
            }
        }
    }

    @State private var selectedTab: VariantSectionTab = .options
    @State private var presentationMode: VariantPresentationMode = .matrix
    @State private var isPresentingColorEditor = false
    @State private var editingProductId: String?
    @State private var isPresentingMediaPicker = false
    @State private var mediaTargetProductId: String?
    @State private var activeStudioMode: VariantStudioMode? = nil
    @State private var copiedHexBanner: String? = nil
    @State private var isPresentingCustomOptionSheet = false
    @State private var isPresentingOptionPalette = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isLoading {
                loadingHeader
                loadingRow
            } else if model.isLegacyUngrouped {
                legacyHeader
                conversionInvitation
                    .disabled(model.isEditingLocked)
            } else if let draft = model.draft {
                studioControlDeck(for: draft)
                    .disabled(model.isEditingLocked)

                if selectedTab == .options {
                    PPAccessoryOptionEditorView(model: model, showHeader: false)
                        .disabled(model.isEditingLocked)
                } else {
                    if draft.hasGenericOptions || presentationMode == .matrix {
                        VStack(alignment: .leading, spacing: 12) {
                            if !draft.hasGenericOptions {
                                modePicker(for: draft)
                            }
                            PPAccessoryVariantMatrixView(
                                model: model,
                                onOpenVariantProduct: onOpenVariantProduct
                            )
                            .disabled(model.isEditingLocked)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            modePicker(for: draft)
                            if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                                HStack(alignment: .top, spacing: 16) {
                                    iPadVariantRail(for: draft)
                                        .frame(width: 220)
                                    if let variant = model.selectedVariant {
                                        variantWorkspace(variant, in: draft)
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            } else {
                                swatchRail(for: draft)
                                if let variant = model.selectedVariant {
                                    variantWorkspace(variant, in: draft)
                                }
                            }
                        }
                    }
                }
            }

            if !model.validationMessages.isEmpty {
                validationList
            }
            if let failure = model.failure {
                failureBanner(failure)
            }
            if let confirmation = model.confirmation {
                confirmationBanner(confirmation)
            }
            if model.isDirty {
                saveDock
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isPresentingMediaPicker) {
            let target = mediaTargetProductId ?? ""
            let remaining = max(
                0,
                PPAccessoryVariantMediaService.maxImagesPerVariant
                    - model.totalImageCount(forProductId: target)
            )
            PPVariantImagePickerSheet(maxSelection: max(1, remaining)) { images in
                if !target.isEmpty {
                    model.addImages(images, forProductId: target)
                }
                isPresentingMediaPicker = false
            }
        }
        .sheet(item: $activeStudioMode) { mode in
            PPAccessoryVariantStudioSheet(
                mode: mode,
                usedColorIdentifiers: model.usedColorIdentifiers,
                isSubmitting: model.isCreatingVariant || model.isSaving,
                existingStagedImages: {
                    if case .edit(let v) = mode {
                        return (model.stagedImages[v.productId] ?? []).map(\.image)
                    }
                    return []
                }(),
                existingVariants: model.draft?.variants ?? [],
                onCreate: { color, options, sku, barcode, retail, wholesale, quantity, images in
                    await model.createAndAttachVariant(
                        color: color,
                        selectedOptions: options,
                        sku: sku,
                        barcode: barcode,
                        retailPrice: retail,
                        wholesalePrice: wholesale,
                        quantity: quantity,
                        images: images
                    )
                },
                onUpdate: { productId, color, options, sku, barcode, retail, wholesale, quantity, newImages, retainedURLs in
                    await model.updateVariant(
                        productId: productId,
                        color: color,
                        selectedOptions: options,
                        sku: sku,
                        barcode: barcode,
                        retailPrice: retail,
                        wholesalePrice: wholesale,
                        quantity: quantity,
                        newImages: newImages,
                        retainedURLs: retainedURLs
                    )
                },
                onOpenFullRecord: { productId in
                    onOpenVariantProduct?(productId)
                },
                errorMessage: {
                    model.failure?.message
                },
                optionDefinitions: model.draft?.optionDefinitions ?? []
            )
        }
        .sheet(isPresented: $isPresentingColorEditor) {
            PPAccessoryVariantColorEditorSheet(
                initialColor: editingProductId.flatMap { model.draft?.variant(forProductId: $0)?.color },
                usedIdentifiers: model.usedColorIdentifiers,
                excludingIdentifier: editingProductId.flatMap {
                    model.draft?.variant(forProductId: $0)?.color.identifier
                }
            ) { chosen in
                if let productId = editingProductId {
                    model.updateColor(chosen, forProductId: productId)
                }
                isPresentingColorEditor = false
            }
        }
        .sheet(isPresented: $isPresentingCustomOptionSheet) {
            PPAccessoryCustomOptionSheet { newOption in
                model.addOption(newOption)
                isPresentingCustomOptionSheet = false
            }
        }
        .sheet(isPresented: $isPresentingOptionPalette) {
            if let draft = model.draft {
                PPOptionPresetActionSheet(
                    draft: draft,
                    onSelectPreset: { preset in
                        model.addOption(preset)
                        isPresentingOptionPalette = false
                    },
                    onSelectCustom: {
                        isPresentingOptionPalette = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isPresentingCustomOptionSheet = true
                        }
                    }
                )
            }
        }
    }

    private func modePicker(for draft: PPAccessoryVariantFamily) -> some View {
        PPVariantPresentationModeSwitch(
            presentationMode: $presentationMode,
            draft: draft,
            selectedVariant: model.selectedVariant
        )
        .padding(.vertical, 2)
    }

    // MARK: - Atelier Studio Command Deck

    private func studioControlDeck(for draft: PPAccessoryVariantFamily) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tier 1: Studio Identity & Dynamic Context Action
            identityAndActionRow(for: draft)

            // Tier 2: Live Telemetry HUD Strip
            telemetryHUD(for: draft)

            // Tier 3: Studio Custom Segmented Switch
            PPVariantSegmentedSwitch(
                selectedTab: $selectedTab,
                draft: draft
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    private func identityAndActionRow(for draft: PPAccessoryVariantFamily) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Chromatic Studio Jewel Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AdminSurface.primary.opacity(0.18),
                                AdminSurface.primary.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
                    )

                Image(systemName: selectedTab == .variants ? "paintpalette.fill" : "slider.horizontal.2.square.on.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab == .variants
                     ? Language.get("Variant_Section_Title", alter: "الألوان والوسائط")
                     : Language.get("Options_Section_Title", alter: "خيارات المنتج"))
                    .font(PPBrandFont.bold(size: 18))
                    .foregroundStyle(AdminSurface.primaryText)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)

                Text(selectedTab == .variants
                     ? Language.get("Variant_Section_Subtitle", alter: "إدارة الألوان والصور والمخزون لكل متغير")
                     : Language.get("Options_Section_Subtitle", alter: "عرّف الخيارات مثل الألوان والمقاسات والأوزان وقيم كل خيار."))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }

            Spacer(minLength: 8)

            if model.canManageVariants {
                contextualActionButton(for: draft)
            }
        }
    }

    @ViewBuilder
    private func contextualActionButton(for draft: PPAccessoryVariantFamily) -> some View {
        if selectedTab == .variants {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                activeStudioMode = .create
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Variant_Add_Action", alter: "إضافة لون"))
                        .font(PPBrandFont.bold(size: 12.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(AdminSurface.primary.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AdminSurface.primary)
            .disabled(
                model.isCreatingVariant ||
                model.isSaving ||
                draft.variantCount >= PPAccessoryVariantContract.maxVariantsPerFamily
            )
            .accessibilityLabel(Language.get("Variant_Add_Action", alter: "إضافة لون"))
            .accessibilityHint(Language.get(
                "Variant_Add_Hint",
                alter: "ينشئ صنفاً مستقلاً بالسعر والرمز الخاصين بهذا اللون ثم يربطه بالمنتج."
            ))
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isPresentingOptionPalette = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Options_Add_Option", alter: "إضافة خيار"))
                        .font(PPBrandFont.bold(size: 12.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(AdminSurface.primary.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AdminSurface.primary)
            .disabled(draft.optionDefinitions.count >= PPAccessoryVariantContract.maxOptionsPerFamily)
            .accessibilityLabel(Language.get("Options_Add_Option", alter: "إضافة خيار"))
        }
    }

    private func telemetryHUD(for draft: PPAccessoryVariantFamily) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Colors / Active Variants Pill
                HStack(spacing: 5) {
                    Image(systemName: draft.hasGenericOptions ? "square.grid.2x2.fill" : "circle.grid.2x1.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AdminSurface.primary)
                    Text(String(
                        format: draft.hasGenericOptions
                            ? Language.get("Inventory_Family_VariantCount", alter: "%@ متغيرات")
                            : Language.get("Inventory_Family_ColourCount", alter: "%@ ألوان"),
                        NSNumber(value: draft.activeVariantCount)
                    ))
                    .font(PPBrandFont.bold(size: 11.5))
                    .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.6))

                // Stock Health Status Pill
                let stockColor = stockIndicatorColor(for: draft.totalAvailableQuantity)
                HStack(spacing: 5) {
                    Circle()
                        .fill(stockColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: stockColor.opacity(0.4), radius: 2)

                    Text(String(
                        format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                        NSNumber(value: draft.totalAvailableQuantity)
                    ))
                    .font(PPBrandFont.bold(size: 11.5))
                    .foregroundStyle(stockColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(stockColor.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(stockColor.opacity(0.2), lineWidth: 0.6))

                // Price Spectrum Pill
                if let summary = familyPriceSummary(draft) {
                    HStack(spacing: 5) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AdminSurface.amber)
                        Text(summary.normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 11.5))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.6))
                    .accessibilityLabel(String(
                        format: Language.get("Inventory_Family_Price_A11y", alter: "نطاق السعر: %@"),
                        summary
                    ))
                }

                // Options Capacity Pill
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(
                        format: Language.get("Options_Capacity_Format", alter: "%d / %d خيارات"),
                        draft.optionDefinitions.count,
                        PPAccessoryVariantContract.maxOptionsPerFamily
                    ))
                    .font(PPBrandFont.bold(size: 11.5))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.6))
            }
            .padding(.vertical, 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func stockIndicatorColor(for qty: Int) -> Color {
        if qty > 5 {
            return AdminSurface.emerald
        } else if qty > 0 {
            return AdminSurface.amber
        } else {
            return AdminSurface.crimson
        }
    }

    private var legacyHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }

            Text(Language.get("Variant_Section_Title", alter: "الألوان والوسائط"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)

            Spacer()
        }
    }

    private var loadingHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.control)
                .frame(width: 38, height: 38)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AdminSurface.control)
                .frame(width: 140, height: 20)

            Spacer()
        }
    }

    private func effectiveRetailPrice(for variant: PPAccessoryVariant) -> Double? {
        guard variant.hasResolvedRetailPrice, let catalog = variant.retailPrice?.doubleValue, catalog >= 0 else {
            return nil
        }
        let resolved = branchPricing.effectiveSellingPrice(
            for: variant.productId,
            fallbackPrice: catalog
        )
        return resolved > 0 ? resolved : nil
    }

    private func formattedRetailPrice(for variant: PPAccessoryVariant) -> String? {
        effectiveRetailPrice(for: variant).map { PetAccessory.formatCurrency(NSNumber(value: $0)) }
    }

    private func familyPriceSummary(_ family: PPAccessoryVariantFamily) -> String? {
        let prices = family.activeVariants.compactMap(effectiveRetailPrice).sorted()
        guard let minimum = prices.first, let maximum = prices.last else { return nil }
        if abs(maximum - minimum) < 0.005 {
            return PetAccessory.formatCurrency(NSNumber(value: minimum))
        }
        return String(
            format: Language.get("Inventory_Family_PriceRange_Format", alter: "%@ – %@"),
            PetAccessory.formatCurrency(NSNumber(value: minimum)),
            PetAccessory.formatCurrency(NSNumber(value: maximum))
        )
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(Language.get("Variant_Loading", alter: "جاري تحميل الألوان..."))
                .font(AdminType.footnote)
                .foregroundStyle(AdminCommandInk.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Legacy Conversion

    private var conversionInvitation: some View {
        let firstVariant = model.draft?.variants.first
        let selectedColor = firstVariant?.color
        let hasSelectedColor = selectedColor != nil && !selectedColor!.identifier.isEmpty

        return VStack(alignment: .leading, spacing: 14) {
            if hasSelectedColor, let color = selectedColor {
                Text(Language.get(
                    "Variant_Convert_ColorAssigned",
                    alter: "تم تحديد لون هذا المنتج. يمكنك تغيير اللون أو حفظ الألوان للمتابعة."
                ))
                .font(AdminType.footnote)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)

                selectedColorCard(color, variant: firstVariant)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Options_Convert_Title", alter: "خيارات وتوليفات المنتج"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Options_Convert_Subtitle", alter: "اختر نوع المتغيرات التي يتوفر بها هذا المنتج للبدء (المقاسات، الأوزان، الألوان، النكهات...):"))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.canManageVariants {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        // 1. Size Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            model.convertWithPresetOption(.presetSize(values: PPAccessoryOptionDefinition.standardSizes))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "ruler.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AdminSurface.emerald)
                                Text(Language.get("Options_Convert_Action_Size", alter: "المقاسات"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                            }
                            .padding(11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // 2. Weight Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            model.convertWithPresetOption(.presetWeight(values: PPAccessoryOptionDefinition.standardWeights))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scalemass.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AdminSurface.amber)
                                Text(Language.get("Options_Convert_Action_Weight", alter: "الأوزان والحجم"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                            }
                            .padding(11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // 3. Color Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            editingProductId = firstVariant?.productId
                            isPresentingColorEditor = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "paintpalette.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                                Text(Language.get("Options_Convert_Action_Color", alter: "الألوان"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                            }
                            .padding(11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // 4. Custom Option Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isPresentingCustomOptionSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.2.square")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.cyan)
                                Text(Language.get("Options_Convert_Action_Custom", alter: "خيار مخصص..."))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                            }
                            .padding(11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: hasSelectedColor)
    }

    private func selectedColorCard(_ color: PPAccessoryVariantColor, variant: PPAccessoryVariant?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.uiColorValue)
                    .frame(width: 44, height: 44)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Circle()
                    .strokeBorder(
                        color.requiresContrastBorder
                            ? AdminSurface.primaryText.opacity(0.35)
                            : Color.white.opacity(0.25),
                        lineWidth: color.requiresContrastBorder ? 1.5 : 1
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color.uiColor.isDarkTone ? Color.white : Color.black.opacity(0.85))
            }
            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(color.localizedName)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Variant_Selected_Badge", alter: "اللون المحدد"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.emerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 6) {
                    Text(verbatim: color.hex)
                        .font(AdminType.caption2.monospaced())
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .environment(\.layoutDirection, .leftToRight)

                    if Language.isRTL() && !color.nameEn.isEmpty {
                        Text(verbatim: "· \(color.nameEn)")
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    } else if !Language.isRTL() && !color.nameAr.isEmpty {
                        Text(verbatim: "· \(color.nameAr)")
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }

            Spacer()

            if model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editingProductId = variant?.productId
                    isPresentingColorEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(Language.get("Variant_Action_EditColor", alter: "تغيير اللون"))
                            .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.surface, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if model.canManageVariants {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                editingProductId = variant?.productId
                isPresentingColorEditor = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            format: Language.get("Variant_Convert_Selected_A11y", alter: "اللون المحدد: %@، رمز اللون: %@"),
            color.accessibilityName,
            color.hex
        ))
        .accessibilityHint(Language.get("Variant_Convert_Selected_Hint", alter: "اضغط لتعديل أو تغيير اللون المحدد لهذا المنتج."))
    }

    // MARK: - Swatch Rail

    private func swatchRail(for draft: PPAccessoryVariantFamily) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(draft.variants, id: \.productId) { variant in
                    swatchChip(variant)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private func swatchChip(_ variant: PPAccessoryVariant) -> some View {
        let isSelected = variant.productId == model.selectedProductId
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                model.select(productId: variant.productId)
            }
        } label: {
            VStack(spacing: 6) {
                // Tactile Color Jewel Orb
                ZStack {
                    Circle()
                        .fill(variant.color.uiColorValue)
                        .frame(width: 40, height: 40)

                    // Specular Highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Circle()
                        .strokeBorder(
                            variant.color.requiresContrastBorder
                                ? AdminSurface.primaryText.opacity(0.30)
                                : Color.white.opacity(0.20),
                            lineWidth: 1
                        )
                        .frame(width: 40, height: 40)

                    if variant.isDefault {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.40))
                                .frame(width: 16, height: 16)
                            Image(systemName: "star.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                        .frame(width: 40, height: 40, alignment: .topTrailing)
                        .offset(x: 2, y: -2)
                    }

                    if variant.isArchived {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 18, height: 18)
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .shadow(color: isSelected ? variant.color.uiColorValue.opacity(0.35) : Color.black.opacity(0.08), radius: isSelected ? 6 : 2, x: 0, y: 2)

                // Color Name
                Text(variant.color.localizedName)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                    .lineLimit(1)

                // Price
                if let price = formattedRetailPrice(for: variant) {
                    Text(price.normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Inventory Badge Pill
                if variant.isArchived {
                    Text(Language.get("Variant_State_Archived", alter: "مؤرشف"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AdminSurface.control, in: Capsule())
                } else if variant.quantity <= 0 {
                    Text(Language.get("Variant_Stock_OutOfStock", alter: "نفد"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.crimson)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                } else {
                    Text(String(
                        format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                        NSNumber(value: variant.quantity)
                    ).normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.emerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AdminSurface.emerald.opacity(0.10), in: Capsule())
                }
            }
            .frame(minWidth: 74, minHeight: 104)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AdminSurface.surface : AdminSurface.control.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? AdminSurface.primary : AdminSurface.hairline,
                        lineWidth: isSelected ? 2 : 0.75
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.08) : Color.clear,
                radius: 8,
                x: 0,
                y: 3
            )
            .opacity(variant.isArchived ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(variant.accessibilityLabel(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// iPad-specific master/detail navigator. It uses a vertical rail instead
    /// of stretching the iPhone horizontal carousel across a wide canvas.
    private func iPadVariantRail(for draft: PPAccessoryVariantFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Variant_iPad_Colours", alter: "ألوان المنتج"))
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(draft.variants, id: \.productId) { variant in
                        let selected = variant.productId == model.selectedProductId
                        Button {
                            if !reduceMotion { UISelectionFeedbackGenerator().selectionChanged() }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                model.select(productId: variant.productId)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(variant.color.uiColorValue)
                                        .frame(width: 30, height: 30)

                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.15)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 30, height: 30)

                                    Circle().strokeBorder(
                                        variant.color.requiresContrastBorder
                                            ? AdminSurface.primaryText.opacity(0.35)
                                            : Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                                    .frame(width: 30, height: 30)

                                    if variant.isDefault {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Color.yellow)
                                            .frame(width: 30, height: 30, alignment: .topTrailing)
                                            .offset(x: 2, y: -2)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(variant.color.localizedName)
                                            .font(AdminType.caption1Bold)
                                            .foregroundStyle(AdminSurface.primaryText)
                                            .lineLimit(1)
                                    }
                                    if let price = formattedRetailPrice(for: variant) {
                                        Text(price.normalizedEnglishDigits)
                                            .font(AdminType.caption2)
                                            .foregroundStyle(AdminCommandInk.secondary)
                                    }
                                }

                                Spacer(minLength: 2)

                                if variant.isArchived {
                                    Text("—")
                                        .font(AdminType.caption2Bold)
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                } else {
                                    Text(variant.quantity.englishDigits)
                                        .font(AdminType.caption2Bold)
                                        .foregroundStyle(variant.quantity > 0 ? AdminSurface.emerald : AdminSurface.crimson)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            (variant.quantity > 0 ? AdminSurface.emerald : AdminSurface.crimson).opacity(0.12),
                                            in: Capsule()
                                        )
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? AdminSurface.surface : AdminSurface.control)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        selected ? AdminSurface.primary : AdminSurface.hairline,
                                        lineWidth: selected ? 1.5 : 0.75
                                    )
                            )
                            .shadow(color: selected ? Color.black.opacity(0.06) : Color.clear, radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(variant.accessibilityLabel(isSelected: selected))
                        .accessibilityValue(formattedRetailPrice(for: variant) ?? "")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Variant Workspace (Spec HUD)

    private func variantWorkspace(
        _ variant: PPAccessoryVariant,
        in draft: PPAccessoryVariantFamily
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero Color Banner with Specular Orb & Copyable HEX
            inspectorHeroBanner(for: variant, in: draft)

            // Spec & Commerce Grid (4 interactive tiles)
            specCommerceGrid(for: variant)

            Divider()
                .foregroundStyle(AdminSurface.hairline)

            // Media Stage
            variantMediaStrip(variant)

            Divider()
                .foregroundStyle(AdminSurface.hairline)

            // Action Control Deck
            if model.canManageVariants {
                variantActions(variant, in: draft)
            }

            // Category-Defining Variant Studio & Catalog Deck
            if model.canManageVariants {
                openProductRecordBanner(for: variant)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func inspectorHeroBanner(
        for variant: PPAccessoryVariant,
        in draft: PPAccessoryVariantFamily
    ) -> some View {
        HStack(spacing: 12) {
            // Large tactile color orb
            ZStack {
                Circle()
                    .fill(variant.color.uiColorValue)
                    .frame(width: 44, height: 44)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Circle()
                    .strokeBorder(
                        variant.color.requiresContrastBorder
                            ? AdminSurface.primaryText.opacity(0.30)
                            : Color.white.opacity(0.20),
                        lineWidth: 1.5
                    )
                    .frame(width: 44, height: 44)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(variant.color.localizedName)
                        .font(AdminType.title3Bold)
                        .foregroundStyle(AdminSurface.primaryText)

                    // Tap to copy HEX pill
                    Button {
                        UIPasteboard.general.string = variant.color.hex
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            copiedHexBanner = variant.color.hex
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if copiedHexBanner == variant.color.hex {
                                    copiedHexBanner = nil
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedHexBanner == variant.color.hex ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(verbatim: variant.color.hex)
                                .font(AdminType.caption2.monospaced())
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.control, in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copiedHexBanner == variant.color.hex ? AdminSurface.emerald : AdminCommandInk.secondary)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(String(format: Language.get("Variant_Copied_Hex", alter: "تم نسخ كود اللون"), variant.color.hex))
                }

                // Bilingual subtitle
                let altName = Language.isRTL() ? variant.color.nameEn : variant.color.nameAr
                if !altName.isEmpty {
                    Text(altName)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
            }

            Spacer()

            // Default Badge or Quick-Default Affordance
            if variant.isDefault {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.emerald)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.emerald.opacity(0.30), lineWidth: 1))
            } else if model.canManageVariants && !variant.isArchived {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.setDefault(productId: variant.productId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 11, weight: .semibold))
                        Text(Language.get("Variant_Quick_SetDefault", alter: "جعله الافتراضي"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func specCommerceGrid(for variant: PPAccessoryVariant) -> some View {
        let retailFormatted = formattedRetailPrice(for: variant)
            ?? Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح")

        let wholesaleSubtitle: String? = {
            guard let wholesale = variant.wholesalePrice, wholesale.doubleValue > 0 else { return nil }
            return String(
                format: Language.get("Wholesale_Price_Format", alter: "جملة: %@"),
                PetAccessory.formatCurrency(wholesale).normalizedEnglishDigits
            )
        }()

        let stockStatusText = variant.quantity > 0
            ? Language.get("Variant_Stock_InStock", alter: "متوفر في المستودع")
            : Language.get("Variant_Stock_OutOfStock", alter: "نفد من المخزون")
        let stockStatusColor = variant.quantity > 0 ? AdminSurface.emerald : AdminSurface.crimson
        let skuValue = variant.sku.trimmingCharacters(in: .whitespacesAndNewlines)
        let barcodeValue = variant.barcode.trimmingCharacters(in: .whitespacesAndNewlines)

        let isBarcodeDuplicate: Bool = {
            let clean = barcodeValue.lowercased()
            guard !clean.isEmpty, let variants = model.draft?.variants else { return false }
            return variants.filter { $0.barcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean }.count > 1
        }()

        let isSkuDuplicate: Bool = {
            let clean = skuValue.lowercased()
            guard !clean.isEmpty, let variants = model.draft?.variants else { return false }
            return variants.filter { $0.sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean }.count > 1
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Tile 1: Price
                specTile(
                    icon: "tag.fill",
                    iconTint: AdminSurface.amber,
                    title: Language.get("Variant_Spec_Retail", alter: "سعر البيع المعتمد"),
                    value: retailFormatted.normalizedEnglishDigits,
                    subtitle: wholesaleSubtitle,
                    subtitleColor: AdminCommandInk.secondary,
                    isMonospaced: false,
                    onTap: model.canManageVariants ? {
                        activeStudioMode = .edit(variant)
                    } : nil
                )

                // Tile 2: Stock
                specTile(
                    icon: "shippingbox.fill",
                    iconTint: stockStatusColor,
                    title: Language.get("Variant_Spec_Stock", alter: "حالة المخزون"),
                    value: String(
                        format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                        NSNumber(value: variant.quantity)
                    ).normalizedEnglishDigits,
                    subtitle: stockStatusText,
                    subtitleColor: stockStatusColor,
                    isMonospaced: false,
                    onTap: model.canManageVariants ? {
                        activeStudioMode = .edit(variant)
                    } : nil
                )
            }

            HStack(spacing: 8) {
                // Tile 3: SKU
                specTile(
                    icon: "number.square.fill",
                    iconTint: isSkuDuplicate ? AdminSurface.crimson : AdminSurface.primary,
                    title: Language.get("Variant_Spec_SKU", alter: "رمز الصنف SKU"),
                    value: skuValue.isEmpty ? Language.get("Variant_Identifier_Unset", alter: "غير محدد") : skuValue,
                    subtitle: isSkuDuplicate ? Language.get("Variant_Error_DuplicateSkuServer", alter: "رمز SKU مستخدم بلون آخر. لكل لون رمز خاص.") : nil,
                    subtitleColor: isSkuDuplicate ? AdminSurface.crimson : nil,
                    isMonospaced: !skuValue.isEmpty,
                    rawCopyValue: skuValue.isEmpty ? nil : skuValue,
                    onTap: model.canManageVariants ? {
                        activeStudioMode = .edit(variant)
                    } : nil
                )

                // Tile 4: Barcode
                specTile(
                    icon: "barcode.viewfinder",
                    iconTint: isBarcodeDuplicate ? AdminSurface.crimson : AdminSurface.primary,
                    title: Language.get("Variant_Spec_Barcode", alter: "الباركود الدولي"),
                    value: barcodeValue.isEmpty ? Language.get("Variant_Identifier_Unset", alter: "غير محدد") : barcodeValue,
                    subtitle: isBarcodeDuplicate ? Language.get("Variant_Error_DuplicateBarcodeServer", alter: "الباركود مستخدم بلون آخر. لكل لون باركود خاص.") : nil,
                    subtitleColor: isBarcodeDuplicate ? AdminSurface.crimson : nil,
                    isMonospaced: !barcodeValue.isEmpty,
                    rawCopyValue: barcodeValue.isEmpty ? nil : barcodeValue,
                    onTap: model.canManageVariants ? {
                        activeStudioMode = .edit(variant)
                    } : nil
                )
            }
        }
    }

    private func specTile(
        icon: String,
        iconTint: Color,
        title: String,
        value: String,
        subtitle: String? = nil,
        subtitleColor: Color? = nil,
        isMonospaced: Bool = false,
        rawCopyValue: String? = nil,
        onTap: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let onTap {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(iconTint)

                    Text(title)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if let copyText = rawCopyValue, !copyText.isEmpty {
                        Button {
                            UIPasteboard.general.string = copyText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                copiedHexBanner = copyText
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    if copiedHexBanner == copyText {
                                        copiedHexBanner = nil
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: copiedHexBanner == copyText ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(copiedHexBanner == copyText ? AdminSurface.emerald : AdminCommandInk.tertiary)
                                .frame(width: 22, height: 22)
                                .background(AdminSurface.surface, in: Circle())
                                .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copyText)
                    } else if onTap != nil {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AdminCommandInk.tertiary)
                            .frame(width: 20, height: 20)
                    }
                }

                Text(verbatim: value.isEmpty ? "—" : value)
                    .font(isMonospaced ? AdminType.footnote.monospaced() : AdminType.calloutBold)
                    .foregroundStyle(value.isEmpty || value == "—" ? AdminCommandInk.tertiary : AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .environment(\.layoutDirection, isMonospaced ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(subtitleColor ?? AdminCommandInk.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    // MARK: - Per-colour Media Strip

    /// Image strip for the selected colour.
    ///
    /// Position 0 is the primary image, which is what legacy consumer clients
    /// render, so it is labelled explicitly rather than implied by order alone.
    private func variantMediaStrip(_ variant: PPAccessoryVariant) -> some View {
        let uploaded = model.images(forProductId: variant.productId)
        let staged = model.staged(forProductId: variant.productId)
        let totalCount = model.totalImageCount(forProductId: variant.productId)
        let maxCount = PPAccessoryVariantMediaService.maxImagesPerVariant

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Media_Title", alter: "صور هذا اللون"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text(verbatim: "\(totalCount.englishDigits)/\(maxCount.englishDigits)")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())
            }

            if uploaded.isEmpty && staged.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    Text(Language.get("Variant_Media_Empty_Tip", alter: "أضف صوراً مخصصة لهذا اللون لتظهر للعملاء عند اختياره في المتجر."))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if model.canManageVariants && model.canAddImage(forProductId: variant.productId) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            activeStudioMode = .edit(variant)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(AdminSurface.primary.opacity(0.10))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AdminSurface.primary)
                                }
                                Text(Language.get("AddPhoto", alter: "إضافة صورة"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .frame(width: 78, height: 78)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundStyle(AdminSurface.primary.opacity(0.40))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(
                            format: Language.get("Variant_Media_Add_A11y", alter: "إضافة صورة للون %@"),
                            variant.color.accessibilityName
                        ))
                    }

                    ForEach(Array(uploaded.enumerated()), id: \.element) { index, url in
                        uploadedThumbnail(url: url, index: index, variant: variant)
                    }

                    ForEach(staged) { item in
                        stagedThumbnail(item, variant: variant)
                    }
                }
                .padding(.vertical, 2)
            }

            if model.hasMediaChanges(forProductId: variant.productId) && model.canManageVariants {
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        Task { await model.saveMedia(forProductId: variant.productId) }
                    } label: {
                        if model.isSavingMedia {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                Language.get("Variant_Media_Save", alter: "حفظ الصور"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(AdminType.caption1Bold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingMedia)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func uploadedThumbnail(url: String, index: Int, variant: PPAccessoryVariant) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.1)
                        Image(systemName: "photo").foregroundStyle(AdminCommandInk.tertiary)
                    }
                default:
                    ZStack {
                        Color.gray.opacity(0.1)
                        ProgressView()
                    }
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            )

            if model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.removeUploadedImage(at: index, forProductId: variant.productId)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel(Language.get("Variant_Media_Remove", alter: "إزالة الصورة"))
            }

            if index == 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text(Language.get("Variant_Media_Primary", alter: "الرئيسية"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65), in: Capsule())
                .padding(4)
                .frame(width: 78, height: 78, alignment: .bottomLeading)
            } else if model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.makePrimaryImage(at: index, forProductId: variant.productId)
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.60), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .frame(width: 78, height: 78, alignment: .bottomLeading)
                .accessibilityLabel(Language.get("Variant_Media_MakePrimary", alter: "تعيين كصورة رئيسية"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func stagedThumbnail(
        _ item: PPAccessoryVariantStagedImage,
        variant: PPAccessoryVariant
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AdminSurface.amber, lineWidth: 1.5)
                )

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.removeStagedImage(id: item.id, forProductId: variant.productId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .padding(4)

            Text(item.uploadedURL == nil
                ? Language.get("Variant_Media_Pending", alter: "غير محفوظة")
                : Language.get("Variant_Media_Uploaded", alter: "تم الرفع"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(AdminSurface.amber.opacity(0.85), in: Capsule())
                .padding(4)
                .frame(width: 78, height: 78, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions & Reordering Control Deck

    private func variantActions(
        _ variant: PPAccessoryVariant,
        in draft: PPAccessoryVariantFamily
    ) -> some View {
        let currentIndex = draft.variants.firstIndex(where: { $0.productId == variant.productId }) ?? 0
        let totalCount = draft.variants.count
        let canMoveEarlier = currentIndex > 0
        let canMoveLater = currentIndex < (totalCount - 1)

        return VStack(spacing: 10) {
            // Row 1: Primary actions (Color edit, Default toggle, Archive)
            HStack(spacing: 8) {
                // Edit Color Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    activeStudioMode = .edit(variant)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(Language.get("Variant_Action_EditColor", alter: "تغيير اللون"))
                            .font(AdminType.caption1Bold)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AdminSurface.primary)

                // Make Default Button (if not already default)
                if !variant.isDefault && !variant.isArchived {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        model.setDefault(productId: variant.productId)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Variant_Action_MakeDefault", alter: "تعيين كافتراضي"))
                                .font(AdminType.caption1Bold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AdminSurface.emerald.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.emerald.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AdminSurface.emerald)
                }

                Spacer(minLength: 4)

                // Archive / Restore Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.setArchived(!variant.isArchived, forProductId: variant.productId)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: variant.isArchived ? "arrow.uturn.backward" : "archivebox.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(variant.isArchived
                            ? Language.get("Variant_Action_Restore", alter: "استعادة")
                            : Language.get("Variant_Action_Archive", alter: "أرشفة"))
                            .font(AdminType.caption1Bold)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        variant.isArchived
                            ? AdminSurface.emerald.opacity(0.10)
                            : (variant.quantity > 0 ? AdminSurface.control.opacity(0.4) : AdminSurface.crimson.opacity(0.08)),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            variant.isArchived
                                ? AdminSurface.emerald.opacity(0.3)
                                : (variant.quantity > 0 ? AdminSurface.hairline : AdminSurface.crimson.opacity(0.2)),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    variant.isArchived
                        ? AdminSurface.emerald
                        : (variant.quantity > 0 ? AdminCommandInk.tertiary : AdminSurface.crimson)
                )
                .disabled(!variant.isArchived && variant.quantity > 0)
            }

            // Row 2: Reordering Bar (Storefront Sequence)
            if totalCount > 1 {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdminCommandInk.tertiary)

                        Text(String(
                            format: Language.get("Variant_Order_Index_Format", alter: "الترتيب: %@ من %@"),
                            (currentIndex + 1).englishDigits,
                            totalCount.englishDigits
                        ))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    }

                    Spacer()

                    // Stepper pill with directional buttons
                    HStack(spacing: 0) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.move(productId: variant.productId, by: -1)
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 36, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canMoveEarlier ? AdminSurface.primary : AdminCommandInk.tertiary.opacity(0.4))
                        .disabled(!canMoveEarlier)
                        .accessibilityLabel(Language.get("Variant_Action_MoveEarlier", alter: "تحريك للأمام"))

                        Divider()
                            .frame(height: 16)
                            .foregroundStyle(AdminSurface.hairline)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.move(productId: variant.productId, by: 1)
                        } label: {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 36, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canMoveLater ? AdminSurface.primary : AdminCommandInk.tertiary.opacity(0.4))
                        .disabled(!canMoveLater)
                        .accessibilityLabel(Language.get("Variant_Action_MoveLater", alter: "تحريك للخلف"))
                    }
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Category-Defining Variant Studio & Catalog Deck

    private func openProductRecordBanner(for variant: PPAccessoryVariant) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            activeStudioMode = .edit(variant)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Variant_OpenProduct", alter: "تعديل سعر ومخزون وصور هذا اللون"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Variant_Studio_Banner_Subtitle", alter: "تعديل فوري للون، الصور، الكمية، السعر، والرموز"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Validation, Failure & Confirmation

    private var validationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.validationMessages, id: \.self) { message in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminSurface.amber)
                    Text(message)
                        .font(PPBrandFont.regular(size: 12.5))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if selectedTab == .options {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                        selectedTab = .variants
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(Language.get("Options_GoToMatrix_Resolve", alter: "انتقل إلى تبويب المتغيرات لحل التعارض"))
                            .font(PPBrandFont.bold(size: 12))
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AdminSurface.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.amber.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func failureBanner(_ failure: PPAccessoryVariantFailureState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: failure.iconName)
                    .foregroundStyle(failure.tint)
                Text(failure.message)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = failure.actionTitle {
                Button(actionTitle) {
                    Task { await performRecovery(failure) }
                }
                .font(AdminType.caption2Bold)
                .buttonStyle(.bordered)
            }

            if failure.preservesDraft {
                Text(Language.get("Variant_Recovery_DraftKept", alter: "تم الاحتفاظ بتعديلاتك."))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(failure.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(failure.tint.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func performRecovery(_ failure: PPAccessoryVariantFailureState) async {
        switch failure.recovery {
        case .reloadAndCompare, .treatAsApplied:
            await model.reloadFromServer()
        case .retrySameCommand, .transferPublicListingFirst:
            await model.save()
        case .correctInput, .permissionDenied, .fatal:
            break
        }
    }

    private func confirmationBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdminSurface.emerald)
            Text(message)
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AdminSurface.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.emerald.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: AdminSurface.emerald.opacity(0.10), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Save Dock

    private var saveDock: some View {
        HStack(spacing: 12) {
            Button(Language.get("Discard", alter: "تجاهل")) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.discardChanges()
            }
            .font(AdminType.calloutBold)
            .buttonStyle(.bordered)
            .disabled(model.isEditingLocked)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(Language.get("Saving", alter: "جارٍ الحفظ..."))
                            .font(AdminType.calloutBold)
                    }
                } else {
                    Label(
                        model.draft?.hasGenericOptions == true
                            ? Language.get("Options_Save_Changes", alter: "حفظ الخيارات والمتغيرات")
                            : Language.get("Variant_Save", alter: "حفظ الألوان"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(AdminType.calloutBold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSaving || !model.canManageVariants || !model.validationMessages.isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

// MARK: - Variant Studio Sheet (Category-Defining Studio)

enum VariantStudioMode: Identifiable {
    case create
    case edit(PPAccessoryVariant)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let v): return "edit-\(v.productId)"
        }
    }

    var isEdit: Bool {
        switch self {
        case .create: return false
        case .edit: return true
        }
    }

    var navigationTitle: String {
        switch self {
        case .create:
            return Language.get("Variant_Studio_CreateTitle", alter: "إضافة لون جديد")
        case .edit(let v):
            return String(format: Language.get("Variant_Studio_EditTitle", alter: "استوديو اللون: %@"), v.color.localizedName)
        }
    }
}

struct PPAccessoryVariantStudioSheet: View {
    let mode: VariantStudioMode
    let usedColorIdentifiers: Set<String>
    let isSubmitting: Bool
    let existingStagedImages: [UIImage]
    let existingVariants: [PPAccessoryVariant]
    let onCreate: (PPAccessoryVariantColor, [String: String], String, String, Double, Double?, Int, [UIImage]) async -> Bool
    let onUpdate: (String, PPAccessoryVariantColor, [String: String], String, String, Double, Double?, Int, [UIImage], [String]?) async -> Bool
    var onOpenFullRecord: ((String) -> Void)? = nil
    var errorMessage: (() -> String?)? = nil
    var optionDefinitions: [PPAccessoryOptionDefinition] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var color: PPAccessoryVariantColor
    @State private var selectedOptions: [String: String]
    @State private var sku: String
    @State private var barcode: String
    @State private var retailPriceText: String
    @State private var wholesaleEnabled: Bool
    @State private var wholesalePriceText: String
    @State private var quantity: Int
    @State private var stagedImages: [UIImage] = []
    @State private var retainedRemoteURLs: [String] = []

    @State private var isChoosingColorFullStudio = false
    @State private var isPresentingImagePicker = false
    @State private var localFailure: String?
    @State private var localSubmitting = false
    @State private var isHexCopied = false

    private let presetColors: [PPAccessoryVariantColor] = PPAccessoryVariantColorLibrary.entries

    init(
        mode: VariantStudioMode,
        usedColorIdentifiers: Set<String>,
        isSubmitting: Bool,
        existingStagedImages: [UIImage] = [],
        existingVariants: [PPAccessoryVariant] = [],
        onCreate: @escaping (PPAccessoryVariantColor, [String: String], String, String, Double, Double?, Int, [UIImage]) async -> Bool,
        onUpdate: @escaping (String, PPAccessoryVariantColor, [String: String], String, String, Double, Double?, Int, [UIImage], [String]?) async -> Bool,
        onOpenFullRecord: ((String) -> Void)? = nil,
        errorMessage: (() -> String?)? = nil,
        optionDefinitions: [PPAccessoryOptionDefinition] = []
    ) {
        self.mode = mode
        self.usedColorIdentifiers = usedColorIdentifiers
        self.isSubmitting = isSubmitting
        self.existingStagedImages = existingStagedImages
        self.existingVariants = existingVariants
        self.onCreate = onCreate
        self.onUpdate = onUpdate
        self.onOpenFullRecord = onOpenFullRecord
        self.errorMessage = errorMessage
        self.optionDefinitions = optionDefinitions

        var initialOptions: [String: String] = [:]
        switch mode {
        case .create:
            let defaultColor = PPAccessoryVariantColorLibrary.entries.first
                ?? PPAccessoryVariantColor(identifier: "black", nameAr: "أسود", nameEn: "Black", hex: "#111111")
            _color = State(initialValue: defaultColor)
            _sku = State(initialValue: "")
            _barcode = State(initialValue: "")
            _retailPriceText = State(initialValue: "")
            _wholesaleEnabled = State(initialValue: false)
            _wholesalePriceText = State(initialValue: "")
            _quantity = State(initialValue: 0)
            _stagedImages = State(initialValue: [])
            _retainedRemoteURLs = State(initialValue: [])
            for def in optionDefinitions where !def.isColorOption && !def.values.isEmpty {
                if let first = def.values.first {
                    initialOptions[def.id] = first.id
                    initialOptions[def.key] = first.id
                }
            }
            _selectedOptions = State(initialValue: initialOptions)
        case .edit(let variant):
            _color = State(initialValue: variant.color)
            _sku = State(initialValue: variant.sku)
            _barcode = State(initialValue: variant.barcode)
            let retailVal = variant.retailPrice?.doubleValue ?? 0
            _retailPriceText = State(initialValue: retailVal > 0 ? String(format: "%.2f", retailVal).replacingOccurrences(of: ".00", with: "") : "")
            let wholesaleVal = variant.wholesalePrice?.doubleValue ?? 0
            _wholesaleEnabled = State(initialValue: wholesaleVal > 0)
            _wholesalePriceText = State(initialValue: wholesaleVal > 0 ? String(format: "%.2f", wholesaleVal).replacingOccurrences(of: ".00", with: "") : "")
            _quantity = State(initialValue: max(0, variant.quantity))
            _stagedImages = State(initialValue: existingStagedImages)
            _retainedRemoteURLs = State(initialValue: variant.media.map(\.remoteURL).filter { !$0.isEmpty })
            initialOptions = variant.selectedOptions
            for def in optionDefinitions where !def.isColorOption && !def.values.isEmpty {
                let current = initialOptions[def.id] ?? initialOptions[def.key]
                if current == nil || current!.isEmpty {
                    if let first = def.values.first {
                        initialOptions[def.id] = first.id
                        initialOptions[def.key] = first.id
                    }
                }
            }
            _selectedOptions = State(initialValue: initialOptions)
        }
    }

    private var retailPrice: Double? {
        Double(retailPriceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var wholesalePrice: Double? {
        guard wholesaleEnabled else { return nil }
        return Double(wholesalePriceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasGenericOptions: Bool {
        !optionDefinitions.filter { !$0.isColorOption && !$0.values.isEmpty }.isEmpty
    }

    private var currentCombinationKey: String {
        var opts = selectedOptions
        if let colorDef = optionDefinitions.first(where: { $0.isColorOption }) {
            opts[colorDef.id] = color.identifier
        }
        opts[PPAccessoryVariantContract.axisColor] = color.identifier
        return PPAccessoryVariantFamily.combinationKey(from: opts)
    }

    private var combinationConflictMessage: String? {
        guard hasGenericOptions else { return nil }
        let currentKey = currentCombinationKey
        for v in existingVariants {
            if case .edit(let current) = mode, v.productId == current.productId { continue }
            let vKey = v.combinationKey.isEmpty ? PPAccessoryVariantFamily.combinationKey(from: v.selectedOptions) : v.combinationKey
            if vKey == currentKey {
                return Language.get("Variant_Error_CombinationTaken", alter: "هذه التوليفة مستخدمة بالفعل في هذا المنتج.")
            }
        }
        return nil
    }

    private var barcodeConflictMessage: String? {
        let clean = barcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }
        for v in existingVariants {
            if case .edit(let current) = mode, v.productId == current.productId { continue }
            if v.barcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean {
                let colorName = v.color.localizedName
                let base = Language.get("Variant_Error_DuplicateBarcodeServer", alter: "الباركود مستخدم بلون آخر. لكل لون باركود خاص.")
                return "\(base) (\(colorName))"
            }
        }
        return nil
    }

    private var skuConflictMessage: String? {
        let clean = sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }
        for v in existingVariants {
            if case .edit(let current) = mode, v.productId == current.productId { continue }
            if v.sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean {
                let colorName = v.color.localizedName
                let base = Language.get("Variant_Error_DuplicateSkuServer", alter: "رمز SKU مستخدم بلون آخر. لكل لون رمز خاص.")
                return "\(base) (\(colorName))"
            }
        }
        return nil
    }

    private var canSubmit: Bool {
        guard !isSubmitting, !localSubmitting else { return false }
        if hasGenericOptions {
            if combinationConflictMessage != nil { return false }
        } else {
            if mode.isEdit {
                if case .edit(let v) = mode {
                    if color.identifier != v.color.identifier && usedColorIdentifiers.contains(color.identifier) {
                        return false
                    }
                }
            } else {
                if usedColorIdentifiers.contains(color.identifier) { return false }
            }
        }
        if barcodeConflictMessage != nil { return false }
        if skuConflictMessage != nil { return false }
        guard let retailPrice, retailPrice.isFinite, retailPrice > 0 else { return false }
        if wholesaleEnabled {
            guard let wholesalePrice, wholesalePrice.isFinite, wholesalePrice > 0 else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    chromaticAtelierCard
                    genericOptionsCard
                    photosAtelierCard
                    stockQuantityDialCard
                    commercePricingCard
                    identifiersCard

                    if mode.isEdit, let onOpenFullRecord, case .edit(let variant) = mode {
                        deepLinkRecordButton(variant: variant, action: onOpenFullRecord)
                    }

                    safetyNoteCard

                    if let localFailure {
                        failureBanner(localFailure)
                    }
                }
                .padding(16)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mode.navigationTitle)
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .disabled(localSubmitting || isSubmitting)
                        .font(PPBrandFont.medium(size: 15))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if localSubmitting || isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(mode.isEdit
                                 ? Language.get("Variant_Studio_Save", alter: "حفظ التعديلات")
                                 : Language.get("Variant_Add_Create", alter: "إنشاء اللون"))
                                .font(PPBrandFont.bold(size: 15))
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            PPBrandFont.registerIfNeeded()
        }
        .sheet(isPresented: $isChoosingColorFullStudio) {
            PPAccessoryVariantColorEditorSheet(
                initialColor: color,
                usedIdentifiers: usedColorIdentifiers,
                excludingIdentifier: mode.isEdit ? color.identifier : nil
            ) { chosen in
                color = chosen
                isChoosingColorFullStudio = false
            }
        }
        .sheet(isPresented: $isPresentingImagePicker) {
            let currentCount = retainedRemoteURLs.count + stagedImages.count
            let remaining = max(1, PPAccessoryVariantMediaService.maxImagesPerVariant - currentCount)
            PPVariantImagePickerSheet(maxSelection: remaining) { picked in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    stagedImages.append(contentsOf: picked)
                }
                isPresentingImagePicker = false
            }
        }
    }

    // MARK: - 1. Chromatic Identity Hero Card

    private var chromaticAtelierCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                // 3D Illuminated Specular Swatch Orb
                ZStack {
                    Circle()
                        .fill(color.uiColorValue)
                        .frame(width: 64, height: 64)
                        .blur(radius: 16)
                        .opacity(0.38)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.uiColorValue,
                                    color.uiColorValue.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().strokeBorder(
                                color.requiresContrastBorder
                                    ? AdminSurface.primaryText.opacity(0.40)
                                    : Color.white.opacity(0.25),
                                lineWidth: color.requiresContrastBorder ? 1.5 : 1
                            )
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                        .overlay(
                            Image(systemName: "circle.hexagongrid.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(color.uiColor.isDarkTone ? Color.white.opacity(0.90) : Color.black.opacity(0.70))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(color.localizedName)
                        .font(AdminType.title3Bold)
                        .foregroundStyle(AdminSurface.primaryText)

                    let altName = Language.isRTL() ? color.nameEn : color.nameAr
                    if !altName.isEmpty {
                        Text(altName)
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    HStack(spacing: 6) {
                        Button {
                            UIPasteboard.general.string = color.hex
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isHexCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { isHexCopied = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isHexCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9, weight: .bold))
                                Text(isHexCopied ? Language.get("Variant_Hex_Copied", alter: "تم النسخ") : color.hex)
                                    .font(AdminType.caption2.monospaced())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AdminSurface.control, in: Capsule())
                            .foregroundStyle(isHexCopied ? AdminSurface.emerald : AdminSurface.primaryText)
                        }
                        .buttonStyle(.plain)

                        if color.requiresContrastBorder {
                            Text(Language.get("Variant_Contrast_Attention", alter: "إطار تباين"))
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminSurface.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.amber.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)
            }

            Divider()
                .foregroundStyle(AdminSurface.hairline)

            // Quick Preset Swatches Rail + Custom Atelier Button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presetColors, id: \.identifier) { preset in
                        let isSelected = color.identifier == preset.identifier
                        let isTaken = !hasGenericOptions && usedColorIdentifiers.contains(preset.identifier) &&
                            (!mode.isEdit || (mode.isEdit && preset.identifier != color.identifier))

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                color = preset
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(isSelected ? AdminSurface.primary : Color.clear, lineWidth: 2)
                                    .frame(width: 38, height: 38)

                                Circle()
                                    .fill(preset.uiColorValue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle().strokeBorder(
                                            preset.requiresContrastBorder ? AdminSurface.primaryText.opacity(0.35) : Color.clear,
                                            lineWidth: 0.75
                                        )
                                    )

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(preset.uiColor.isDarkTone ? Color.white : Color.black)
                                }

                                if isTaken && !isSelected {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTaken)
                        .opacity(isTaken && !isSelected ? 0.35 : 1.0)
                        .accessibilityLabel(preset.accessibilityName)
                    }

                    // Full Custom Studio Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isChoosingColorFullStudio = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Variant_Studio_Custom_Palette", alter: "استوديو الألوان الكامل"))
                                .font(AdminType.caption2Bold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1))
                        .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - 1.5. Generic Options & Specifications Card

    @ViewBuilder
    private var genericOptionsCard: some View {
        let activeGenericDefs = optionDefinitions.filter { !$0.isColorOption && !$0.values.isEmpty }
        if !activeGenericDefs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Studio_Options_Title", alter: "خيارات ومواصفات هذا المتغير"))
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                }

                Text(Language.get("Variant_Studio_Options_Subtitle", alter: "حدد قيمة كل خيار لربط هذا المتغير بالمواصفات المحددة بدقة داخل النظام."))
                    .font(PPBrandFont.regular(size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)

                ForEach(activeGenericDefs, id: \.id) { def in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(def.localizedName)
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundStyle(AdminSurface.primaryText)

                            Spacer()

                            let chosenValId = selectedOptions[def.id] ?? selectedOptions[def.key]
                            if let chosenVal = def.values.first(where: { $0.id == chosenValId }) {
                                Text(chosenVal.localizedName)
                                    .font(PPBrandFont.bold(size: 12))
                                    .foregroundStyle(AdminSurface.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(def.values, id: \.id) { val in
                                    let isSelected = (selectedOptions[def.id] == val.id) || (selectedOptions[def.key] == val.id)
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                            selectedOptions[def.id] = val.id
                                            selectedOptions[def.key] = val.id
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .black))
                                            }
                                            Text(val.localizedName)
                                                .font(isSelected ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? AdminSurface.primary : AdminSurface.control,
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule().strokeBorder(
                                                isSelected ? AdminSurface.primary : AdminSurface.hairline,
                                                lineWidth: 1
                                            )
                                        )
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    if def.id != activeGenericDefs.last?.id {
                        Divider().foregroundStyle(AdminSurface.hairline)
                    }
                }

                if let conflict = combinationConflictMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AdminSurface.crimson)
                        Text(conflict)
                            .font(PPBrandFont.medium(size: 12))
                            .foregroundStyle(AdminSurface.crimson)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.crimson.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(combinationConflictMessage != nil ? AdminSurface.crimson : AdminSurface.hairline, lineWidth: combinationConflictMessage != nil ? 1.5 : 1)
            )
        }
    }

    // MARK: - 2. Color Photos Darkroom & Atelier Card

    private var photosAtelierCard: some View {
        let totalCount = retainedRemoteURLs.count + stagedImages.count
        let maxCount = PPAccessoryVariantMediaService.maxImagesPerVariant
        let canAdd = totalCount < maxCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Studio_Photos_Title", alter: "صور هذا اللون"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text(verbatim: "\(totalCount.englishDigits)/\(maxCount.englishDigits)")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())

                if canAdd {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isPresentingImagePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Variant_Studio_Photos_Add", alter: "إضافة صور"))
                                .font(AdminType.caption2Bold)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(Language.get("Variant_Studio_Photos_Subtitle", alter: "الصور المخصصة لهذا اللون. تظهر تلقائياً للعميل عند اختيار هذا اللون."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)

            // Photos Reel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Add Photo Card Tile
                    if canAdd {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isPresentingImagePicker = true
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(AdminSurface.primary.opacity(0.10))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(AdminSurface.primary)
                                }
                                Text(Language.get("Variant_Studio_Photos_Add", alter: "إضافة صور"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .frame(width: 82, height: 82)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundStyle(AdminSurface.primary.opacity(0.35))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Existing Remote Uploaded Images
                    ForEach(Array(retainedRemoteURLs.enumerated()), id: \.element) { index, url in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                promoteRemoteImageToPrimary(at: index)
                            } label: {
                                AsyncImage(url: URL(string: url)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    case .failure:
                                        Color.gray.opacity(0.15)
                                    default:
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                .frame(width: 82, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(index == 0 ? AdminSurface.amber : AdminSurface.hairline, lineWidth: index == 0 ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Delete button
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    _ = retainedRemoteURLs.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                            .padding(4)

                            // Primary Cover Badge
                            if index == 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                    Text(Language.get("Variant_Studio_Photos_Primary", alter: "الرئيسية"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundStyle(AdminSurface.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.70), in: Capsule())
                                .padding(4)
                                .frame(width: 82, height: 82, alignment: .bottomLeading)
                            }
                        }
                    }

                    // Newly Staged Local Images
                    ForEach(Array(stagedImages.enumerated()), id: \.offset) { index, img in
                        let isTotalPrimary = retainedRemoteURLs.isEmpty && index == 0
                        ZStack(alignment: .topTrailing) {
                            Button {
                                promoteStagedImageToPrimary(at: index)
                            } label: {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 82, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(isTotalPrimary ? AdminSurface.amber : AdminSurface.primary.opacity(0.4), lineWidth: isTotalPrimary ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            // Delete button
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    _ = stagedImages.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                            .padding(4)

                            // Primary badge or New badge
                            if isTotalPrimary {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                    Text(Language.get("Variant_Studio_Photos_Primary", alter: "الرئيسية"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundStyle(AdminSurface.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.70), in: Capsule())
                                .padding(4)
                                .frame(width: 82, height: 82, alignment: .bottomLeading)
                            } else {
                                Text(Language.get("New", alter: "جديدة"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary, in: Capsule())
                                    .padding(4)
                                    .frame(width: 82, height: 82, alignment: .bottomLeading)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if totalCount > 1 {
                Text(Language.get("Variant_Studio_Photos_MakePrimary", alter: "اضغط على أي صورة لجعلها الرئيسية"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func promoteRemoteImageToPrimary(at index: Int) {
        guard index > 0, retainedRemoteURLs.indices.contains(index) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            let item = retainedRemoteURLs.remove(at: index)
            retainedRemoteURLs.insert(item, at: 0)
        }
    }

    private func promoteStagedImageToPrimary(at index: Int) {
        guard stagedImages.indices.contains(index) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            let item = stagedImages.remove(at: index)
            // If there are remote URLs, place at front of staged or bring to index 0
            if retainedRemoteURLs.isEmpty {
                stagedImages.insert(item, at: 0)
            } else {
                stagedImages.insert(item, at: 0)
            }
        }
    }

    // MARK: - 3. Tactile Stock & Quantity Dial Card

    private var stockQuantityDialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Studio_Stock_Title", alter: "الكمية والمخزون الحالي"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Dynamic Health Pill
                if quantity == 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "slash.circle.fill")
                            .font(.system(size: 10))
                        Text(Language.get("Variant_Studio_Stock_Zero", alter: "نفد المخزون (0 حبة)"))
                            .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.crimson)
                } else if quantity <= 5 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(String(
                            format: Language.get("Variant_Studio_Stock_Low_Format", alter: "مخزون محدود (%@ حبة)"),
                            NSNumber(value: quantity)
                        ).normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AdminSurface.amber.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.amber)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text(String(
                            format: Language.get("Variant_Studio_Stock_InStock_Format", alter: "متوفر (%@ حبة)"),
                            NSNumber(value: quantity)
                        ).normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.emerald)
                }
            }

            // Tactile Stepper Box
            HStack(spacing: 16) {
                // Decrement Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                        quantity = max(0, quantity - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.control, in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        .foregroundStyle(quantity > 0 ? AdminSurface.primaryText : AdminCommandInk.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(quantity <= 0)

                Spacer()

                // Numeric Display / Direct Input
                VStack(spacing: 2) {
                    Text(verbatim: "\(quantity.englishDigits)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(quantity > 0 ? AdminSurface.primaryText : AdminSurface.crimson)
                        .monospacedDigit()
                    Text(Language.get("Piece", alter: "حبة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer()

                // Increment Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                        quantity += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.primary.opacity(0.12), in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.primary.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Quick Intake Shortcuts Bar
            HStack(spacing: 8) {
                stockQuickPill("+1", delta: 1)
                stockQuickPill("+5", delta: 5)
                stockQuickPill("+10", delta: 10)
                stockQuickPill("+25", delta: 25)
                stockQuickPill("+50", delta: 50)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        quantity = 0
                    }
                } label: {
                    Text(Language.get("Reset", alter: "تصفير"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.crimson)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.crimson.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func stockQuickPill(_ title: String, delta: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                quantity += delta
            }
        } label: {
            Text(title)
                .font(AdminType.caption2Bold.monospacedDigit())
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Commerce & Pricing Card

    private var commercePricingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Variant_Add_Pricing", alter: "تسعير هذا اللون"), systemImage: "tag.fill")
                    .font(PPBrandFont.bold(size: 15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            priceInputField(
                title: Language.get("Variant_RetailPrice", alter: "سعر البيع"),
                text: $retailPriceText,
                required: true
            )

            Toggle(isOn: $wholesaleEnabled.animation(reduceMotion ? nil : .easeInOut(duration: 0.16))) {
                Text(Language.get("Variant_Add_Wholesale", alter: "سعر جملة مستقل"))
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            if wholesaleEnabled {
                priceInputField(
                    title: Language.get("Variant_WholesalePrice", alter: "سعر الجملة"),
                    text: $wholesalePriceText,
                    required: true
                )

                // Margin Delta Calculation
                if let ret = retailPrice, let who = wholesalePrice, ret > 0, who > 0 {
                    let delta = ret - who
                    let marginPercent = Int(round((delta / ret) * 100.0))
                    HStack(spacing: 6) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(
                            format: Language.get("Variant_Studio_Margin_Delta", alter: "فارق السعر: %@ (هامش الربح: %@%%)"),
                            String(format: "%.2f QAR", delta).normalizedEnglishDigits,
                            "\(marginPercent)".normalizedEnglishDigits
                        ))
                        .font(PPBrandFont.bold(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (delta >= 0 ? AdminSurface.emerald : AdminSurface.crimson).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .foregroundStyle(delta >= 0 ? AdminSurface.emerald : AdminSurface.crimson)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func priceInputField(title: String, text: Binding<String>, required: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("QAR", alter: "ر.ق"))
                    .font(PPBrandFont.medium(size: 11))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
            Spacer()
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(width: 130)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(title)
        }
    }

    // MARK: - 5. Identifiers Card (SKU & Barcode)

    private var identifiersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Language.get("Variant_Add_Identifiers", alter: "هوية اللون في المخزون"), systemImage: "barcode.viewfinder")
                .font(PPBrandFont.bold(size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            // Barcode Section with Camera Scanner & PP Generator
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Language.get("CatalogIntake_BarcodeLabel", alter: "الباركود"))
                        .font(PPBrandFont.bold(size: 13))
                        .foregroundStyle(AdminSurface.primaryText)

                    if barcodeConflictMessage != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(Language.get("Validation_Duplicate", alter: "مكرر"))
                                .font(PPBrandFont.bold(size: 11))
                        }
                        .foregroundStyle(AdminSurface.crimson)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .foregroundStyle(barcodeConflictMessage != nil ? AdminSurface.crimson : AdminCommandInk.secondary)

                    TextField(Language.get("CatalogIntake_BarcodePlaceholder", alter: "امسح أو اكتب الباركود"), text: $barcode)
                        .font(AdminType.body.monospaced())
                        .englishAlphanumericInput(text: $barcode)
                        .environment(\.layoutDirection, .leftToRight)

                    if !barcode.isEmpty {
                        Button {
                            UIPasteboard.general.string = barcode
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            barcode = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                    }

                    Button {
                        generatePPBarcode()
                    } label: {
                        HStack(spacing: 2) {
                            Text("PP")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .frame(height: 36)
                        .padding(.horizontal, 7)
                        .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("CatalogIntake_GeneratePPBarcode", alter: "توليد باركود PP"))

                    AdminBarcodeScanButton { scanned in
                        barcode = scanned
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(minHeight: 48)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            barcodeConflictMessage != nil ? AdminSurface.crimson : AdminSurface.hairline,
                            lineWidth: barcodeConflictMessage != nil ? 1.5 : 0.75
                        )
                )

                if let conflict = barcodeConflictMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdminSurface.crimson)
                            .padding(.top, 1)
                        Text(conflict)
                            .font(PPBrandFont.bold(size: 12))
                            .foregroundStyle(AdminSurface.crimson)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // SKU Section with Generator
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Language.get("CatalogIntake_SKULabel", alter: "رمز المنتج (SKU)"))
                        .font(PPBrandFont.bold(size: 13))
                        .foregroundStyle(AdminSurface.primaryText)

                    if skuConflictMessage != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(Language.get("Validation_Duplicate", alter: "مكرر"))
                                .font(PPBrandFont.bold(size: 11))
                        }
                        .foregroundStyle(AdminSurface.crimson)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Button {
                        generateVariantSKU()
                    } label: {
                        Label(Language.get("Generate_SKU_Auto", alter: "توليد SKU"), systemImage: "wand.and.stars")
                            .font(PPBrandFont.bold(size: 12))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(skuConflictMessage != nil ? AdminSurface.crimson : AdminCommandInk.secondary)

                    TextField(Language.get("CatalogIntake_SKUPlaceholder", alter: "مثال: CLR-102"), text: $sku)
                        .font(AdminType.body.monospaced())
                        .englishAlphanumericInput(text: $sku)
                        .environment(\.layoutDirection, .leftToRight)

                    if !sku.isEmpty {
                        Button {
                            UIPasteboard.general.string = sku
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            sku = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            skuConflictMessage != nil ? AdminSurface.crimson : AdminSurface.hairline,
                            lineWidth: skuConflictMessage != nil ? 1.5 : 0.75
                        )
                )

                if let conflict = skuConflictMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdminSurface.crimson)
                            .padding(.top, 1)
                        Text(conflict)
                            .font(PPBrandFont.bold(size: 12))
                            .foregroundStyle(AdminSurface.crimson)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func generatePPBarcode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let timestamp = Int(Date().timeIntervalSince1970) % 1_000_000_000
        let randomDigit = Int.random(in: 0...9)
        barcode = String(format: "PP%09d%d", timestamp, randomDigit)
    }

    private func generateVariantSKU() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let colorTag = color.nameEn.filter { $0.isLetter }.prefix(3).uppercased()
        let prefix = colorTag.isEmpty ? "CLR" : String(colorTag)
        sku = "\(prefix)-\(Int.random(in: 100...999))"
    }

    // MARK: - 6. Safety & Deep-link Records

    private func deepLinkRecordButton(variant: PPAccessoryVariant, action: @escaping (String) -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            action(variant.productId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Variant_Studio_OpenFullRecord", alter: "فتح السجل الكامل في إدارة الأصناف"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)
                Spacer()
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
            .padding(12)
            .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var safetyNoteCard: some View {
        Label(
            Language.get(
                "Variant_Studio_SafetyNote",
                alter: "ترتبط كل حركة مخزون وصور بهذا اللون بالتحديد وبشكل مستقل وآمن داخل النظام."
            ),
            systemImage: "checkmark.shield.fill"
        )
        .font(PPBrandFont.regular(size: 12))
        .foregroundStyle(AdminCommandInk.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func failureBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(PPBrandFont.medium(size: 13))
            .foregroundStyle(AdminSurface.crimson)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AdminSurface.crimson.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit, let retailPrice else { return }
        localSubmitting = true
        localFailure = nil
        Task { @MainActor in
            let success: Bool
            switch mode {
            case .create:
                success = await onCreate(
                    color,
                    selectedOptions,
                    sku,
                    barcode,
                    retailPrice,
                    wholesalePrice,
                    quantity,
                    stagedImages
                )
            case .edit(let variant):
                success = await onUpdate(
                    variant.productId,
                    color,
                    selectedOptions,
                    sku,
                    barcode,
                    retailPrice,
                    wholesalePrice,
                    quantity,
                    stagedImages,
                    retainedRemoteURLs
                )
            }
            localSubmitting = false
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                localFailure = errorMessage?() ?? Language.get(
                    "Variant_Studio_SaveFailed",
                    alter: "تعذر حفظ التعديلات. لم يتم فقدان أي بيانات، يرجى المحاولة مرة أخرى."
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Colour editor sheet (Category-Defining Atelier)

struct PPAccessoryVariantColorEditorSheet: View {
    let initialColor: PPAccessoryVariantColor?
    let usedIdentifiers: Set<String>
    /// The colour currently assigned to the variant being edited, which must not
    /// count as a duplicate of itself.
    let excludingIdentifier: String?
    let onPick: (PPAccessoryVariantColor) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var hex: String = "#CCCCCC"
    @State private var identifier: String = ""
    @State private var isCustom = false
    @State private var selectedSwiftUIColor: Color = .gray
    @State private var isHexCopied = false

    private let neutralsIds: Set<String> = ["black", "white", "grey", "beige", "brown"]
    private let warmIds: Set<String> = ["crimson-red", "rose-pink", "amber-orange", "sun-yellow"]
    private let coolIds: Set<String> = ["forest-green", "teal", "ocean-blue", "navy", "violet"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heroStageCard
                    paletteGroupsSection
                    customStudioSection

                    if let problem {
                        conflictWarningBanner(problem)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Variant_ChooseColor", alter: "اختيار اللون"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Variant_ChooseColor", alter: "اختيار اللون"))
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminCommandInk.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        onPick(previewColor)
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("Done", alter: "تم"))
                                .font(AdminType.calloutBold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(problem == nil ? AdminSurface.primary : AdminSurface.primary.opacity(0.35))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(problem != nil)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear(perform: seed)
    }

    private func seed() {
        if let initialColor, !initialColor.identifier.isEmpty {
            nameAr = initialColor.nameAr
            nameEn = initialColor.nameEn
            hex = initialColor.hex
            identifier = initialColor.identifier
            selectedSwiftUIColor = initialColor.uiColorValue
        } else if let firstPreset = PPAccessoryVariantColorLibrary.entries.first {
            nameAr = firstPreset.nameAr
            nameEn = firstPreset.nameEn
            hex = firstPreset.hex
            identifier = firstPreset.identifier
            selectedSwiftUIColor = firstPreset.uiColorValue
        }
    }

    // MARK: - Hero Swatch Stage Card

    private var heroStageCard: some View {
        VStack(spacing: 14) {
            // Dimensional Glowing Swatch
            ZStack {
                // Dynamic Breathing Ambient Glow
                Circle()
                    .fill(previewColor.uiColorValue)
                    .frame(width: 88, height: 88)
                    .blur(radius: 22)
                    .opacity(0.42)

                // Tactile Color Disc
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                previewColor.uiColorValue,
                                previewColor.uiColorValue.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().strokeBorder(
                            previewColor.requiresContrastBorder
                                ? AdminSurface.primaryText.opacity(0.40)
                                : Color.white.opacity(0.25),
                            lineWidth: previewColor.requiresContrastBorder ? 1.5 : 1
                        )
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
                    .overlay(
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(previewColor.uiColor.isDarkTone ? Color.white.opacity(0.90) : Color.black.opacity(0.70))
                    )
            }
            .padding(.top, 4)

            // Dynamic Bilingual Title Header
            VStack(spacing: 4) {
                Text(previewColor.localizedName.isEmpty ? Language.get("Variant_Custom", alter: "لون مخصص") : previewColor.localizedName)
                    .font(AdminType.title3Bold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                if !previewColor.nameEn.isEmpty && Language.isRTL() {
                    Text(previewColor.nameEn)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                } else if !previewColor.nameAr.isEmpty && !Language.isRTL() {
                    Text(previewColor.nameAr)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }
            }

            // Hex & Contrast Indicators
            HStack(spacing: 8) {
                // Hex Capsule with tap-to-copy
                Button {
                    UIPasteboard.general.string = previewColor.hex
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHexCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { isHexCopied = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isHexCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isHexCopied ? Language.get("Variant_Hex_Copied", alter: "تم نسخ رمز اللون") : previewColor.hex)
                            .font(AdminType.caption2.monospaced())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(isHexCopied ? AdminSurface.emerald : AdminSurface.primaryText)
                }
                .buttonStyle(.plain)

                // Live Contrast Status
                HStack(spacing: 4) {
                    Image(systemName: previewColor.requiresContrastBorder ? "eye.trianglebadge.exclamationmark" : "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(previewColor.requiresContrastBorder ? AdminSurface.amber : AdminSurface.emerald)
                    Text(previewColor.requiresContrastBorder
                         ? Language.get("Variant_Contrast_Attention", alter: "قد يحتاج لإطار تباين")
                         : Language.get("Variant_Contrast_Optimal", alter: "تباين ممتاز (مقروء بوضوح)"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Harmonized Palettes Section

    private var paletteGroupsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    Language.get("Variant_Preset_Palettes", alter: "المجموعات اللونية المتناسقة"),
                    systemImage: "paintpalette.fill"
                )
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)

                Spacer()
            }

            paletteGroupRow(
                title: Language.get("Variant_Palette_Neutrals", alter: "الأساسيات والمحايدة"),
                entries: PPAccessoryVariantColorLibrary.entries.filter { neutralsIds.contains($0.identifier) }
            )

            paletteGroupRow(
                title: Language.get("Variant_Palette_Warm", alter: "الدرجات الدافئة والحيوية"),
                entries: PPAccessoryVariantColorLibrary.entries.filter { warmIds.contains($0.identifier) }
            )

            paletteGroupRow(
                title: Language.get("Variant_Palette_Cool", alter: "الدرجات الباردة والعميقة"),
                entries: PPAccessoryVariantColorLibrary.entries.filter { coolIds.contains($0.identifier) }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func paletteGroupRow(title: String, entries: [PPAccessoryVariantColor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .padding(.horizontal, 2)

            HStack(spacing: 12) {
                ForEach(entries, id: \.identifier) { entry in
                    atelierChip(entry)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func atelierChip(_ entry: PPAccessoryVariantColor) -> some View {
        let isSelected = (previewColor.identifier == entry.identifier) ||
            (!isCustom && hex.uppercased() == entry.hex.uppercased())
        let isTaken = usedIdentifiers.contains(entry.identifier) && entry.identifier != excludingIdentifier

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                nameAr = entry.nameAr
                nameEn = entry.nameEn
                hex = entry.hex
                identifier = entry.identifier
                isCustom = false
                selectedSwiftUIColor = entry.uiColorValue
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Outer animated selection ring
                    Circle()
                        .strokeBorder(
                            isSelected ? AdminSurface.primary : Color.clear,
                            lineWidth: 2.5
                        )
                        .frame(width: 48, height: 48)

                    // Color Disc
                    Circle()
                        .fill(entry.uiColorValue)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().strokeBorder(
                                entry.requiresContrastBorder
                                    ? AdminSurface.primaryText.opacity(0.35)
                                    : Color.clear,
                                lineWidth: 1
                            )
                        )
                        .shadow(color: Color.black.opacity(isSelected ? 0.20 : 0.06), radius: isSelected ? 4 : 2, x: 0, y: 1)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(entry.uiColor.isDarkTone ? Color.white : Color.black.opacity(0.85))
                    }

                    if isTaken {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .scaleEffect(isSelected ? 1.08 : 1.0)

                Text(entry.localizedName)
                    .font(isSelected ? AdminType.caption2Bold : AdminType.caption2)
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 54)
            }
            .frame(minWidth: 48)
            .opacity(isTaken ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
        .accessibilityLabel(
            isTaken
                ? "\(entry.accessibilityName), \(Language.get("Variant_AlreadyUsed", alter: "مستخدم بالفعل"))"
                : entry.accessibilityName
        )
    }

    // MARK: - Custom Color Studio Deck

    private var customStudioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    Language.get("Variant_Custom_Section", alter: "استوديو التخصيص والمسميات"),
                    systemImage: "slider.horizontal.3"
                )
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            spectrumPickerRow
            hexInputRow
            Divider().padding(.vertical, 2)
            bilingualNameFields
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private var spectrumPickerRow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 42)
                .opacity(0.85)

            HStack {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(Language.get("Variant_Spectrum_Picker", alter: "لوحة الألوان التفاعلية"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(.white)
                Spacer()
                ColorPicker("", selection: $selectedSwiftUIColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: selectedSwiftUIColor) { newColor in
                        handleColorPickerChange(newColor)
                    }
            }
            .padding(.horizontal, 14)
        }
    }

    private func handleColorPickerChange(_ newColor: Color) {
        let derived = UIColor(newColor).purePetsHex
        hex = derived
        isCustom = true
        for entry in PPAccessoryVariantColorLibrary.entries {
            if entry.hex.caseInsensitiveCompare(derived) == .orderedSame {
                nameAr = entry.nameAr
                nameEn = entry.nameEn
                identifier = entry.identifier
                break
            }
        }
    }

    private var hexDigitsBinding: Binding<String> {
        Binding(
            get: {
                hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            },
            set: { newVal in
                let cleaned = newVal.filter { "0123456789ABCDEFabcdef".contains($0) }.uppercased()
                let formatted = "#" + String(cleaned.prefix(6))
                hex = formatted
                isCustom = true
                if formatted.count == 7 {
                    let temp = PPAccessoryVariantColor(identifier: "temp", nameAr: "", nameEn: "", hex: formatted)
                    selectedSwiftUIColor = temp.uiColorValue
                }
            }
        )
    }

    private var hexInputRow: some View {
        HStack {
            Text(Language.get("Variant_Hex", alter: "قيمة اللون"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)

            Spacer()

            HStack(spacing: 6) {
                Text("#")
                    .font(AdminType.caption2Bold.monospaced())
                    .foregroundStyle(AdminCommandInk.tertiary)

                TextField("RRGGBB", text: hexDigitsBinding)
                    .font(AdminType.caption1.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 76)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PPAccessoryVariantColor.isValidHex(hex) ? AdminSurface.hairline : AdminSurface.crimson, lineWidth: 1)
            )
        }
    }

    private var bilingualNameFields: some View {
        VStack(spacing: 12) {
            arabicNameField
            englishNameField
        }
    }

    private var arabicNameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(Language.get("Variant_NameAr", alter: "الاسم بالعربية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text("\(nameAr.count)/60")
                    .font(AdminType.caption2.monospaced())
                    .foregroundStyle(nameAr.count > 60 ? AdminSurface.crimson : AdminCommandInk.tertiary)
            }

            HStack {
                TextField(Language.get("Variant_NameAr", alter: "الاسم بالعربية"), text: $nameAr)
                    .font(AdminType.callout)
                    .multilineTextAlignment(Language.isRTL() ? .leading : .trailing)
                    .onChange(of: nameAr) { _ in isCustom = true }

                if !nameAr.isEmpty {
                    Button {
                        nameAr = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var englishNameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(Language.get("Variant_NameEn", alter: "الاسم بالإنجليزية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text("\(nameEn.count)/60")
                    .font(AdminType.caption2.monospaced())
                    .foregroundStyle(nameEn.count > 60 ? AdminSurface.crimson : AdminCommandInk.tertiary)
            }

            HStack {
                TextField(Language.get("Variant_NameEn", alter: "الاسم بالإنجليزية"), text: $nameEn)
                    .font(AdminType.callout)
                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: nameEn) { _ in isCustom = true }

                if !nameEn.isEmpty {
                    Button {
                        nameEn = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Conflict Warning Banner

    private func conflictWarningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AdminSurface.amber)
            Text(message)
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.amber.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// The colour that would be produced by the current fields. A custom colour
    /// derives a stable identifier so the operator never has to invent one.
    private var previewColor: PPAccessoryVariantColor {
        let resolvedIdentifier: String
        if isCustom || identifier.isEmpty {
            resolvedIdentifier = PPAccessoryVariantColor.derivedIdentifier(fromName: nameEn, hex: hex)
        } else {
            resolvedIdentifier = identifier
        }
        return PPAccessoryVariantColor(
            identifier: resolvedIdentifier,
            nameAr: nameAr,
            nameEn: nameEn,
            hex: hex
        )
    }

    private var problem: String? {
        let candidate = previewColor
        if let message = candidate.validationMessage { return message }
        if usedIdentifiers.contains(candidate.identifier),
           candidate.identifier != excludingIdentifier {
            return Language.get("Variant_Error_ColorTaken", alter: "هذا اللون مستخدم بالفعل في هذا المنتج.")
        }
        return nil
    }
}

// MARK: - Atelier Color Extensions

fileprivate extension UIColor {
    var purePetsHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            let rgb = (Int(round(r * 255)) << 16) | (Int(round(g * 255)) << 8) | Int(round(b * 255))
            return String(format: "#%06X", rgb)
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &a) {
            let val = Int(round(white * 255))
            let rgb = (val << 16) | (val << 8) | val
            return String(format: "#%06X", rgb)
        }
        return "#CCCCCC"
    }

    var isDarkTone: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance < 0.55
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &a) {
            return white < 0.55
        }
        return false
    }
}


// MARK: - Image picker
//
// A file-local picker, matching the existing pattern in this module: the
// equivalents in PPAccessoryEditorView.swift and PPLivePetBasicDataEditorView.swift
// are both file-private, so they cannot be shared.

struct PPVariantImagePickerSheet: UIViewControllerRepresentable {
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PPVariantImagePickerSheet

        init(_ parent: PPVariantImagePickerSheet) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else {
                parent.onPicked([])
                return
            }

            var images: [UIImage] = []
            let group = DispatchGroup()
            let lock = NSLock()

            for result in results where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        images.append(image)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [parent] in
                parent.onPicked(images)
            }
        }
    }
}
