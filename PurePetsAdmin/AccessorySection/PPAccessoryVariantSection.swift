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

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var validationMessages: [String] = []
    @Published private(set) var failure: PPAccessoryVariantFailureState?
    @Published private(set) var confirmation: String?

    // MARK: Per-colour media
    //
    // Staged per colour so switching colours never mixes one colour's pictures
    // into another's. Uploads are deferred until the media save, matching the
    // editor's existing discipline.
    @Published var stagedImages: [String: [PPAccessoryVariantStagedImage]] = [:]
    @Published var retainedImageURLs: [String: [String]] = [:]
    @Published private(set) var isSavingMedia = false
    private var originalImageURLs: [String: [String]] = [:]
    private var imageMetadataByURL: [String: [String: Any]] = [:]
    private var pendingMediaCommandId: [String: String] = [:]

    /// Retained so a `retrySameCommand` recovery reuses the exact key the server
    /// already bound, rather than minting a new one and risking a second effect.
    private var pendingCommandId: String?
    /// The colour that held the public listing when the draft was loaded. Used to
    /// order the listing transfer when the default changes.
    private var baselineDefaultProductId: String = ""

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

    private func apply(loaded family: PPAccessoryVariantFamily) {
        baseline = family
        draft = family.copyForEditing()
        baselineDefaultProductId = family.defaultVariantProductId
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
    func saveMedia(forProductId productId: String) async {
        guard let variant = draft?.variant(forProductId: productId) else { return }
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
                colorId: variant.color.identifier
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
                expectedRevision: variant.revision
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
            showInAppMarket: existing.showInAppMarket,
            revision: existing.revision,
            media: existing.media
        )
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

    /// Colours already used, so the picker can prevent a duplicate rather than
    /// letting the server reject it.
    var usedColorIdentifiers: Set<String> {
        Set((draft?.variants ?? []).map(\.color.identifier).filter { !$0.isEmpty })
    }

    func revalidate() {
        validationMessages = draft?.validationMessages() ?? []
    }

    func discardChanges() {
        guard let baseline else { return }
        draft = baseline.copyForEditing()
        validationMessages = []
        failure = nil
    }

    // MARK: Save

    func save() async {
        guard let draft else { return }
        revalidate()
        guard validationMessages.isEmpty else { return }

        isSaving = true
        failure = nil
        confirmation = nil
        defer { isSaving = false }

        let commandId = pendingCommandId ?? "variant-family-\(UUID().uuidString)"
        pendingCommandId = commandId

        // The outgoing default is only relevant when the default actually moved.
        let outgoing = draft.defaultVariantProductId == baselineDefaultProductId
            ? nil
            : baselineDefaultProductId

        do {
            let result = try await PPAccessoryVariantService.shared.saveFamily(
                draft,
                commandId: commandId,
                transferringListingFrom: outgoing
            )
            pendingCommandId = nil
            confirmation = result.idempotent
                ? Language.get("Variant_Save_AlreadyApplied", alter: "كانت هذه التغييرات محفوظة بالفعل.")
                : Language.get("Variant_Save_Confirmed", alter: "تم حفظ الألوان.")
            // Reload from the server so the editor shows the confirmed state,
            // including the family id minted by a create.
            let reloaded = try await PPAccessoryVariantService.shared.loadFamily(familyId: result.familyId)
            apply(loaded: reloaded)
        } catch {
            let state = PPAccessoryVariantFailureState(error: error)
            // Only a same-command retry may reuse the key. Any other outcome
            // must not reuse it: the server may already have bound it.
            if !state.allowsSameCommandRetry { pendingCommandId = nil }
            failure = state
            if !state.validationMessages.isEmpty { validationMessages = state.validationMessages }
        }
    }

    /// Reload used by the `reloadAndCompare` recovery. The draft is deliberately
    /// preserved so the operator can see what they had before deciding.
    func reloadFromServer() async {
        guard let familyId = baseline?.familyId, !familyId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let reloaded = try await PPAccessoryVariantService.shared.loadFamily(familyId: familyId)
            baseline = reloaded
            baselineDefaultProductId = reloaded.defaultVariantProductId
            failure = nil
            revalidate()
        } catch {
            failure = PPAccessoryVariantFailureState(error: error)
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

// MARK: - Section view

struct PPAccessoryVariantSection: View {
    @ObservedObject var model: PPAccessoryVariantSectionModel
    /// Invoked when the operator asks to open a colour's own product record,
    /// where SKU, barcode, price, stock and images are edited.
    var onOpenVariantProduct: ((String) -> Void)?

    @State private var isPresentingColorEditor = false
    @State private var editingProductId: String?
    @State private var isPresentingMediaPicker = false
    @State private var mediaTargetProductId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isLoading {
                loadingRow
            } else if model.isLegacyUngrouped {
                conversionInvitation
            } else if let draft = model.draft {
                swatchRail(for: draft)
                if let variant = model.selectedVariant {
                    variantWorkspace(variant, in: draft)
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
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Label(
                Language.get("Variant_Section_Title", alter: "الألوان والوسائط"),
                systemImage: "paintpalette.fill"
            )
            .font(AdminType.headline)
            .foregroundStyle(AdminSurface.primaryText)

            Spacer()

            if let draft = model.draft, !model.isLegacyUngrouped {
                // Family availability is a projection of the member products.
                Text(verbatim: "\(draft.activeVariantCount.englishDigits) · \(draft.totalAvailableQuantity.englishDigits)")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .accessibilityLabel(
                        String(
                            format: Language.get(
                                "Variant_Section_Summary_A11y",
                                alter: "%@ لون، %@ متوفر إجمالاً"
                            ),
                            NSNumber(value: draft.activeVariantCount),
                            NSNumber(value: draft.totalAvailableQuantity)
                        )
                    )
            }
        }
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

    // MARK: Legacy conversion

    private var conversionInvitation: some View {
        let firstVariant = model.draft?.variants.first
        let selectedColor = firstVariant?.color
        let hasSelectedColor = selectedColor != nil && !selectedColor!.identifier.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
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
                Text(Language.get(
                    "Variant_Convert_Explainer",
                    alter: "هذا المنتج بلون واحد. أضف لونًا لتحويله إلى مجموعة ألوان دون فقدان المخزون أو السجل."
                ))
                .font(AdminType.footnote)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.canManageVariants {
                    Button {
                        editingProductId = firstVariant?.productId
                        isPresentingColorEditor = true
                    } label: {
                        Label(
                            Language.get("Variant_Convert_Action", alter: "تحديد لون هذا المنتج"),
                            systemImage: "paintpalette"
                        )
                        .font(AdminType.calloutBold)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(Language.get(
                        "Variant_Convert_Hint",
                        alter: "يحدد لون المنتج الحالي قبل إضافة ألوان أخرى."
                    ))
                }
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasSelectedColor)
    }

    private func selectedColorCard(_ color: PPAccessoryVariantColor, variant: PPAccessoryVariant?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.uiColorValue)
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if model.canManageVariants {
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

    // MARK: Swatch rail

    private func swatchRail(for draft: PPAccessoryVariantFamily) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(draft.variants, id: \.productId) { variant in
                    swatchChip(variant)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func swatchChip(_ variant: PPAccessoryVariant) -> some View {
        let isSelected = variant.productId == model.selectedProductId
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.select(productId: variant.productId)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(variant.color.uiColorValue)
                        .frame(width: 34, height: 34)
                    // A light or transparent-looking swatch needs a visible edge,
                    // otherwise white reads as an empty hole on a light surface.
                    Circle()
                        .strokeBorder(
                            variant.color.requiresContrastBorder
                                ? AdminSurface.primaryText.opacity(0.35)
                                : Color.clear,
                            lineWidth: 1
                        )
                        .frame(width: 34, height: 34)
                    if variant.isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                            .frame(width: 34, height: 34, alignment: .bottomTrailing)
                    }
                    if variant.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    }
                }

                // Colour is never communicated by the swatch alone.
                Text(variant.color.localizedName)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                    .lineLimit(1)

                Text(
                    variant.isArchived
                        ? Language.get("Variant_State_Archived", alter: "مؤرشف")
                        : "\(variant.quantity.englishDigits)"
                )
                .font(AdminType.caption2)
                .foregroundStyle(variant.quantity <= 0 && !variant.isArchived
                    ? AdminSurface.crimson
                    : AdminCommandInk.tertiary)
            }
            // 44pt minimum touch target.
            .frame(minWidth: 62, minHeight: 78)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
            )
            .opacity(variant.isArchived ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(variant.accessibilityLabel(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Variant workspace

    private func variantWorkspace(
        _ variant: PPAccessoryVariant,
        in draft: PPAccessoryVariantFamily
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(variant.color.localizedName)
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(verbatim: variant.color.hex)
                    .font(AdminType.caption2.monospaced())
                    .foregroundStyle(AdminCommandInk.tertiary)
                    // A hex code is an identifier: keep it LTR inside Arabic.
                    .environment(\.layoutDirection, .leftToRight)
                Spacer()
                if variant.isDefault {
                    Text(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.emerald)
                }
            }

            // Server-owned identifiers, shown read-only. SKU and barcode belong
            // to the colour's own product record; editing them here would make
            // this screen a second writer.
            identifierRow(
                title: Language.get("Group_SKU", alter: "رمز الصنف SKU"),
                value: variant.sku
            )
            identifierRow(
                title: Language.get("Barcode", alter: "الباركود"),
                value: variant.barcode
            )
            identifierRow(
                title: Language.get("Variant_Availability", alter: "المتوفر"),
                value: "\(variant.quantity.englishDigits)"
            )

            Divider().padding(.vertical, 2)

            variantMediaStrip(variant)

            if model.canManageVariants {
                variantActions(variant, in: draft)
            }

            if let onOpenVariantProduct {
                Button {
                    onOpenVariantProduct(variant.productId)
                } label: {
                    Label(
                        Language.get("Variant_OpenProduct", alter: "تعديل سعر ومخزون وصور هذا اللون"),
                        systemImage: "arrow.up.forward.square"
                    )
                    .font(AdminType.caption2Bold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Per-colour media

    /// Image strip for the selected colour.
    ///
    /// Position 0 is the primary image, which is what legacy consumer clients
    /// render, so it is labelled explicitly rather than implied by order alone.
    private func variantMediaStrip(_ variant: PPAccessoryVariant) -> some View {
        let uploaded = model.images(forProductId: variant.productId)
        let staged = model.staged(forProductId: variant.productId)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("Variant_Media_Title", alter: "صور هذا اللون"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text(verbatim: "\(model.totalImageCount(forProductId: variant.productId).englishDigits)/\(PPAccessoryVariantMediaService.maxImagesPerVariant.englishDigits)")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            if uploaded.isEmpty && staged.isEmpty {
                Text(Language.get("Variant_Media_Empty", alter: "لا توجد صور لهذا اللون بعد."))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.canManageVariants && model.canAddImage(forProductId: variant.productId) {
                        Button {
                            mediaTargetProductId = variant.productId
                            isPresentingMediaPicker = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 20, weight: .semibold))
                                Text(Language.get("AddPhoto", alter: "إضافة صورة"))
                                    .font(AdminType.caption2Bold)
                            }
                            .frame(width: 72, height: 72)
                            .foregroundStyle(AdminSurface.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundStyle(AdminSurface.primary.opacity(0.4))
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
                            Text(Language.get("Variant_Media_Save", alter: "حفظ الصور"))
                                .font(AdminType.caption2Bold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingMedia)
                }
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
                    Image(systemName: "photo").foregroundStyle(AdminCommandInk.tertiary)
                default:
                    ProgressView()
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if model.canManageVariants {
                Button {
                    model.removeUploadedImage(at: index, forProductId: variant.productId)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(3)
                .accessibilityLabel(Language.get("Variant_Media_Remove", alter: "إزالة الصورة"))
            }

            if index == 0 {
                Text(Language.get("Variant_Media_Primary", alter: "الرئيسية"))
                    .font(AdminType.caption2Bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
                    .frame(width: 72, height: 72, alignment: .bottomLeading)
            } else if model.canManageVariants {
                Button {
                    model.makePrimaryImage(at: index, forProductId: variant.productId)
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 11, weight: .bold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(3)
                .frame(width: 72, height: 72, alignment: .bottomLeading)
                .accessibilityLabel(Language.get("Variant_Media_MakePrimary", alter: "تعيين كصورة رئيسية"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            format: index == 0
                ? Language.get("Variant_Media_Primary_A11y", alter: "الصورة الرئيسية للون %@")
                : Language.get("Variant_Media_Item_A11y", alter: "صورة %@ للون %@"),
            index == 0 ? variant.color.accessibilityName : NSNumber(value: index + 1).stringValue,
            variant.color.accessibilityName
        ))
    }

    private func stagedThumbnail(
        _ item: PPAccessoryVariantStagedImage,
        variant: PPAccessoryVariant
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AdminSurface.amber, lineWidth: 1.5)
                )

            Button {
                model.removeStagedImage(id: item.id, forProductId: variant.productId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(3)

            // An already-uploaded staged image is distinguished from a pending
            // one, so a retry after a partial failure is understandable.
            Text(item.uploadedURL == nil
                ? Language.get("Variant_Media_Pending", alter: "غير محفوظة")
                : Language.get("Variant_Media_Uploaded", alter: "تم الرفع"))
                .font(AdminType.caption2Bold)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(3)
                .frame(width: 72, height: 72, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private func identifierRow(title: String, value: String) -> some View {        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Spacer()
            Text(verbatim: value.isEmpty ? "—" : value)
                .font(AdminType.footnote.monospaced())
                .foregroundStyle(AdminSurface.primaryText)
                // SKU and barcode stay LTR even in an Arabic layout.
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
        }
    }

    private func variantActions(
        _ variant: PPAccessoryVariant,
        in draft: PPAccessoryVariantFamily
    ) -> some View {
        HStack(spacing: 8) {
            actionButton(
                title: Language.get("Variant_Action_EditColor", alter: "تغيير اللون"),
                systemImage: "paintbrush"
            ) {
                editingProductId = variant.productId
                isPresentingColorEditor = true
            }

            if !variant.isDefault && !variant.isArchived {
                actionButton(
                    title: Language.get("Variant_Action_MakeDefault", alter: "تعيين كافتراضي"),
                    systemImage: "star"
                ) {
                    model.setDefault(productId: variant.productId)
                }
            }

            // Reordering uses leading/trailing semantics, not left/right, so the
            // arrows stay correct in Arabic.
            actionButton(title: "", systemImage: "chevron.backward") {
                model.move(productId: variant.productId, by: -1)
            }
            .accessibilityLabel(Language.get("Variant_Action_MoveEarlier", alter: "تحريك للأمام"))

            actionButton(title: "", systemImage: "chevron.forward") {
                model.move(productId: variant.productId, by: 1)
            }
            .accessibilityLabel(Language.get("Variant_Action_MoveLater", alter: "تحريك للخلف"))

            Spacer()

            actionButton(
                title: variant.isArchived
                    ? Language.get("Variant_Action_Restore", alter: "استعادة")
                    : Language.get("Variant_Action_Archive", alter: "أرشفة"),
                systemImage: variant.isArchived ? "arrow.uturn.backward" : "archivebox"
            ) {
                model.setArchived(!variant.isArchived, forProductId: variant.productId)
            }
            // Archiving a colour holding stock is refused by the server; disable
            // it here so the operator is not invited into a guaranteed failure.
            .disabled(!variant.isArchived && variant.quantity > 0)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                if !title.isEmpty {
                    Text(title).font(AdminType.caption2Bold)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AdminSurface.primary)
    }

    // MARK: Validation, failure, confirmation

    private var validationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.validationMessages, id: \.self) { message in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.amber)
                    Text(message)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AdminSurface.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(10)
        .background(failure.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(AdminSurface.emerald)
            Text(message)
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AdminSurface.emerald.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Save dock

    private var saveDock: some View {
        HStack(spacing: 10) {
            Button(Language.get("Discard", alter: "تجاهل")) {
                model.discardChanges()
            }
            .font(AdminType.caption2Bold)
            .buttonStyle(.bordered)

            Button {
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(Language.get("Variant_Save", alter: "حفظ الألوان"))
                        .font(AdminType.calloutBold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSaving || !model.canManageVariants || !model.validationMessages.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
                    .onChange(of: selectedSwiftUIColor) { _, newColor in
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
                    .onChange(of: nameAr) { _, _ in isCustom = true }

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
                    .onChange(of: nameEn) { _, _ in isCustom = true }

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

private struct PPVariantImagePickerSheet: UIViewControllerRepresentable {
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
