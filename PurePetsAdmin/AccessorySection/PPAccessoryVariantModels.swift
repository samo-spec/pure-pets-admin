//
//  PPAccessoryVariantModels.swift
//  PurePetsAdmin
//
//  Typed domain layer for accessory colour variants.
//
//  ── Architecture ────────────────────────────────────────────────────────────
//  One logical product ("family") groups several sellable `petAccessories`
//  documents, one per colour. Each colour keeps its own product id, SKU,
//  barcode, images, stock, branch inventory, lots and commerce override,
//  because every inventory subsystem in Infra is keyed on the product id.
//
//  ── Ownership ───────────────────────────────────────────────────────────────
//  This file is domain-only: parsing, serialization, validation, comparison and
//  dirty-state. It performs no Firebase read or write, holds no singleton and
//  owns no UI. `upsertProductVariantFamily` in Pure Pets Infra is the single
//  writer of family and variant identity; this layer only builds the request it
//  is given and interprets the reply. `AppMgr` remains the global state owner
//  and `PPInventoryCommandService` remains the mutation facade.
//
//  A product with no family membership is represented as a single-variant
//  family by `PPAccessoryVariantFamily.legacySingleVariant(from:)`, so the
//  editor has exactly one code path for both shapes.
//

import Foundation
import UIKit

// MARK: - Contract constants

/// Mirrors the Infra contract. Kept in one place so a client never spells a
/// server key inline.
@objc public final class PPAccessoryVariantContract: NSObject {
    /// Callable that owns every family/variant identity write.
    @objc public static let callableName = "upsertProductVariantFamily"
    /// Only supported envelope version.
    @objc public static let contractVersion = 2
    /// Only supported variant axis today.
    @objc public static let axisColor = "color"
    /// Server bound; a family cannot exceed this, so one transaction always suffices.
    @objc public static let maxVariantsPerFamily = 40
    /// Schema version stamped on each member product.
    @objc public static let variantSchemaVersion = 1

    /// Live pets are individually tracked and are excluded from colour families.
    @objc public static let livePetKindType = 3

    private override init() { super.init() }
}

// MARK: - Colour

/// A colour identity.
///
/// `identifier` is canonical and stable. Names and hex are display data and may
/// be edited later without breaking an order line, a receipt or a stock record,
/// so neither a localized name nor the hex value may ever act as identity.
@objc public final class PPAccessoryVariantColor: NSObject, @unchecked Sendable {
    @objc public let identifier: String
    @objc public let nameAr: String
    @objc public let nameEn: String
    /// Normalized uppercase `#RRGGBB`.
    @objc public let hex: String

    @objc public init(identifier: String, nameAr: String, nameEn: String, hex: String) {
        self.identifier = PPAccessoryVariantColor.normalizedIdentifier(identifier)
        self.nameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hex = PPAccessoryVariantColor.normalizedHex(hex)
        super.init()
    }

    /// Parses the `variantAttributes.color` map stamped on a member product, or
    /// the `variants[].color` map on a family document.
    @objc public convenience init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let identifier = PPAccessoryVariantColor.string(dictionary["id"])
        guard !identifier.isEmpty else { return nil }
        self.init(
            identifier: identifier,
            nameAr: PPAccessoryVariantColor.string(dictionary["nameAr"]),
            nameEn: PPAccessoryVariantColor.string(dictionary["nameEn"]),
            hex: PPAccessoryVariantColor.string(dictionary["hex"])
        )
    }

    /// Payload shape the callable expects.
    @objc public func payload() -> [String: Any] {
        [
            "id": identifier,
            "nameAr": nameAr,
            "nameEn": nameEn,
            "hex": hex,
        ]
    }

    /// Display name for the active language. A swatch alone never communicates a
    /// colour, so every surface must render text alongside it.
    @objc public var localizedName: String {
        if Language.isRTL() {
            return nameAr.isEmpty ? nameEn : nameAr
        }
        return nameEn.isEmpty ? nameAr : nameEn
    }

    /// Accessibility label. Deliberately the colour name, never "coloured circle".
    @objc public var accessibilityName: String {
        let primary = localizedName
        return primary.isEmpty ? identifier : primary
    }

    @objc public var uiColor: UIColor {
        PPAccessoryVariantColor.color(fromHex: hex) ?? .clear
    }

    /// True when the swatch is too close to the surface to be seen unaided and
    /// therefore needs a visible border. Covers white, near-white and
    /// transparent-looking colours, which the plan calls out explicitly.
    @objc public var requiresContrastBorder: Bool {
        guard let color = PPAccessoryVariantColor.color(fromHex: hex) else { return true }
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getWhite(&white, alpha: &alpha) else { return true }
        return white > 0.82 || alpha < 0.95
    }

    // MARK: Validation

    @objc public static func isValidIdentifier(_ value: String) -> Bool {
        let candidate = normalizedIdentifier(value)
        guard !candidate.isEmpty, candidate.count <= 64 else { return false }
        // Mirrors the server rule: lowercase alphanumeric, dash or underscore,
        // and must not start with a separator.
        let pattern = "^[a-z0-9][a-z0-9_-]*$"
        return candidate.range(of: pattern, options: .regularExpression) != nil
    }

    @objc public static func isValidHex(_ value: String) -> Bool {
        normalizedHex(value).range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
    }

    /// Server-side validation is authoritative. This mirrors it so the operator
    /// sees the problem before a round trip, never to replace it.
    @objc public var validationMessage: String? {
        if !PPAccessoryVariantColor.isValidIdentifier(identifier) {
            return Language.get("Variant_Error_ColorIdentifier", alter: "معرف اللون غير صالح.")
        }
        if nameAr.isEmpty || nameAr.count > 60 {
            return Language.get("Variant_Error_ColorNameAr", alter: "اسم اللون بالعربية مطلوب.")
        }
        if nameEn.isEmpty || nameEn.count > 60 {
            return Language.get("Variant_Error_ColorNameEn", alter: "اسم اللون بالإنجليزية مطلوب.")
        }
        if !PPAccessoryVariantColor.isValidHex(hex) {
            return Language.get("Variant_Error_ColorHex", alter: "قيمة اللون غير صالحة.")
        }
        return nil
    }

    // MARK: Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PPAccessoryVariantColor else { return false }
        return identifier == other.identifier
            && nameAr == other.nameAr
            && nameEn == other.nameEn
            && hex == other.hex
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(identifier)
        hasher.combine(nameAr)
        hasher.combine(nameEn)
        hasher.combine(hex)
        return hasher.finalize()
    }

    /// Identity-only comparison, for duplicate detection where display edits
    /// must not count as a different colour.
    @objc public func hasSameIdentity(as other: PPAccessoryVariantColor) -> Bool {
        identifier == other.identifier
    }

    // MARK: Helpers

    private static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedHex(_ value: String) -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !candidate.hasPrefix("#") { candidate = "#" + candidate }
        // Expand #RGB shorthand so the server always receives #RRGGBB.
        if candidate.count == 4 {
            let components = Array(candidate.dropFirst())
            candidate = "#" + components.map { "\($0)\($0)" }.joined()
        }
        return candidate
    }

    /// Derives a stable identifier from an English colour name, for the
    /// "custom colour" path where the operator does not supply one.
    @objc public static func derivedIdentifier(fromName name: String, hex: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // ASCII-only slugs keep the identifier readable in logs and URLs. An
        // Arabic-only name yields an empty slug, so fall back to the hex digits,
        // which are stable for that swatch.
        if slug.isEmpty || slug.range(of: "^[a-z0-9]", options: .regularExpression) == nil {
            let digits = normalizedHex(hex).dropFirst().lowercased()
            slug = "custom-\(digits)"
        }
        return String(slug.prefix(64))
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let normalized = normalizedHex(hex)
        guard normalized.count == 7 else { return nil }
        let digits = normalized.dropFirst()
        var value: UInt64 = 0
        guard Scanner(string: String(digits)).scanHexInt64(&value) else { return nil }
        return UIColor(
            red: CGFloat((value & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((value & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(value & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Media

/// One image belonging to a specific colour variant.
///
/// `remoteURL` is empty while an image is still a local draft; `localIdentifier`
/// is empty once it has been uploaded. Keeping both lets a failed upload be
/// retried without losing the operator's selection.
@objc public final class PPAccessoryVariantMedia: NSObject, @unchecked Sendable {
    @objc public let remoteURL: String
    @objc public let localIdentifier: String
    @objc public let width: Int
    @objc public let height: Int
    @objc public let blurHash: String

    @objc public init(
        remoteURL: String,
        localIdentifier: String = "",
        width: Int = 0,
        height: Int = 0,
        blurHash: String = ""
    ) {
        self.remoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localIdentifier = localIdentifier
        self.width = max(0, width)
        self.height = max(0, height)
        self.blurHash = blurHash
        super.init()
    }

    @objc public var isUploaded: Bool { !remoteURL.isEmpty }
    @objc public var isPendingUpload: Bool { remoteURL.isEmpty && !localIdentifier.isEmpty }

    /// `imageMeta` entry shape already used by the catalog payload.
    @objc public func metadataPayload() -> [String: Any] {
        var payload: [String: Any] = ["url": remoteURL]
        if width > 0 { payload["width"] = width }
        if height > 0 { payload["height"] = height }
        return payload
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PPAccessoryVariantMedia else { return false }
        return remoteURL == other.remoteURL
            && localIdentifier == other.localIdentifier
            && width == other.width
            && height == other.height
            && blurHash == other.blurHash
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(remoteURL)
        hasher.combine(localIdentifier)
        return hasher.finalize()
    }
}

// MARK: - Variant

/// One sellable colour. Backed by a real `petAccessories` document, so it keeps
/// its own identity, stock and history.
@objc public final class PPAccessoryVariant: NSObject, @unchecked Sendable {
    @objc public let productId: String
    @objc public let color: PPAccessoryVariantColor
    @objc public var sortOrder: Int
    @objc public var isArchived: Bool
    @objc public var isDefault: Bool

    /// Catalog projection. Read-only here: these fields stay owned by
    /// `validateInventoryChange`, and the family callable only validates them.
    @objc public let sku: String
    @objc public let barcode: String
    @objc public let primaryImageURL: String
    @objc public let quantity: Int
    /// Public/default retail projection for this exact color product. The
    /// authoritative branch override is resolved at presentation/POS time from
    /// BranchProductCommerce; the family never owns a price.
    @objc public let retailPrice: NSNumber?
    @objc public let wholesalePrice: NSNumber?
    @objc public let hasResolvedRetailPrice: Bool
    @objc public let showInAppMarket: Bool
    /// Product revision observed when this variant was loaded, for optimistic
    /// concurrency on the family save.
    @objc public let revision: Int

    @objc public var media: [PPAccessoryVariantMedia]

    @objc public init(
        productId: String,
        color: PPAccessoryVariantColor,
        sortOrder: Int,
        isArchived: Bool = false,
        isDefault: Bool = false,
        sku: String = "",
        barcode: String = "",
        primaryImageURL: String = "",
        quantity: Int = 0,
        retailPrice: NSNumber? = nil,
        wholesalePrice: NSNumber? = nil,
        hasResolvedRetailPrice: Bool = false,
        showInAppMarket: Bool = false,
        revision: Int = 0,
        media: [PPAccessoryVariantMedia] = []
    ) {
        self.productId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
        self.sortOrder = max(0, sortOrder)
        self.isArchived = isArchived
        self.isDefault = isDefault
        self.sku = sku
        self.barcode = barcode
        self.primaryImageURL = primaryImageURL
        self.quantity = max(0, quantity)
        self.retailPrice = retailPrice
        self.wholesalePrice = wholesalePrice
        self.hasResolvedRetailPrice = hasResolvedRetailPrice
        self.showInAppMarket = showInAppMarket
        self.revision = max(0, revision)
        self.media = media
        super.init()
    }

    /// Builds a variant from a loaded product document.
    @objc public convenience init?(accessory: PetAccessory) {
        guard let colorMap = accessory.variantColorDictionary,
              let color = PPAccessoryVariantColor(dictionary: colorMap) else { return nil }
        self.init(
            productId: accessory.accessoryID,
            color: color,
            sortOrder: accessory.variantSortOrder,
            isArchived: accessory.isArchived,
            isDefault: accessory.isDefaultVariant,
            sku: accessory.sku ?? "",
            barcode: accessory.barcode ?? "",
            primaryImageURL: PetAccessory.firstImageURL(for: accessory)?.absoluteString ?? "",
            quantity: accessory.quantity,
            retailPrice: accessory.hasResolvedSellingPrice ? accessory.finalPrice : nil,
            wholesalePrice: accessory.wholesalePrice,
            hasResolvedRetailPrice: accessory.hasResolvedSellingPrice,
            showInAppMarket: accessory.showInAppMarket,
            revision: accessory.revision,
            media: (accessory.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) }
        )
    }

    /// Payload entry the callable expects. Only identity and ordering — never a
    /// catalog field this command does not own.
    @objc public func payload() -> [String: Any] {
        [
            "productId": productId,
            "color": color.payload(),
            "sortOrder": sortOrder,
            "isArchived": isArchived,
        ]
    }

    @objc public var isSellable: Bool { !isArchived }

    /// VoiceOver label: colour, then availability, then selection state. Never
    /// just the colour, and never only a swatch.
    @objc public func accessibilityLabel(isSelected: Bool) -> String {
        var parts: [String] = [color.accessibilityName]
        if isArchived {
            parts.append(Language.get("Variant_State_Archived", alter: "مؤرشف"))
        } else if quantity <= 0 {
            parts.append(Language.get("Variant_State_OutOfStock", alter: "غير متوفر"))
        } else {
            let template = Language.get("Variant_State_AvailableCount", alter: "%@ متوفر")
            parts.append(String(format: template, NSNumber(value: quantity)))
        }
        if isDefault {
            parts.append(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
        }
        if isSelected {
            parts.append(Language.get("Variant_State_Selected", alter: "محدد"))
        }
        return parts.joined(separator: ", ")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PPAccessoryVariant else { return false }
        return productId == other.productId
            && color.isEqual(other.color)
            && sortOrder == other.sortOrder
            && isArchived == other.isArchived
            && isDefault == other.isDefault
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(productId)
        hasher.combine(color.identifier)
        return hasher.finalize()
    }
}

// MARK: - Family

/// A logical product with one colour axis.
@objc public final class PPAccessoryVariantFamily: NSObject, @unchecked Sendable {
    /// Empty for a family that has not been created on the server yet, and for
    /// the synthetic legacy single-variant family.
    @objc public let familyId: String
    @objc public var name: String
    @objc public var nameEn: String
    @objc public var desc: String
    @objc public var descEn: String
    @objc public let accessKindType: Int
    @objc public var accessoryCategoryID: String
    @objc public var petMainCategoryID: Int
    @objc public var petSubCategoryID: Int
    @objc public let variantAxis: String
    @objc public var variants: [PPAccessoryVariant]
    @objc public var defaultVariantProductId: String
    @objc public var active: Bool
    @objc public let isArchived: Bool
    /// Family revision observed at load, required for an update.
    @objc public let revision: Int
    /// True when this is a synthetic wrapper around a product that has no
    /// family on the server. Determines whether a save is `create` or `update`.
    @objc public let isLegacySingleVariant: Bool

    @objc public init(
        familyId: String,
        name: String,
        nameEn: String,
        desc: String = "",
        descEn: String = "",
        accessKindType: Int,
        accessoryCategoryID: String = "",
        petMainCategoryID: Int = 0,
        petSubCategoryID: Int = 0,
        variantAxis: String = PPAccessoryVariantContract.axisColor,
        variants: [PPAccessoryVariant],
        defaultVariantProductId: String,
        active: Bool = true,
        isArchived: Bool = false,
        revision: Int = 0,
        isLegacySingleVariant: Bool = false
    ) {
        self.familyId = familyId
        self.name = name
        self.nameEn = nameEn
        self.desc = desc
        self.descEn = descEn
        self.accessKindType = accessKindType
        self.accessoryCategoryID = accessoryCategoryID
        self.petMainCategoryID = petMainCategoryID
        self.petSubCategoryID = petSubCategoryID
        self.variantAxis = variantAxis
        self.variants = variants.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder
                ? lhs.productId < rhs.productId
                : lhs.sortOrder < rhs.sortOrder
        }
        self.defaultVariantProductId = defaultVariantProductId
        self.active = active
        self.isArchived = isArchived
        self.revision = max(0, revision)
        self.isLegacySingleVariant = isLegacySingleVariant
        super.init()
    }

    // MARK: Parsing

    /// Parses a `ProductFamilies/{familyId}` document together with its already
    /// loaded member products.
    ///
    /// The family document is the ordering authority, and the member products
    /// carry live stock. Members absent from `products` are skipped rather than
    /// synthesized, so the editor never shows a colour it cannot resolve.
    @objc public static func family(
        fromDocument document: [String: Any],
        documentID: String,
        products: [String: PetAccessory]
    ) -> PPAccessoryVariantFamily? {
        let orderedIds = (document["variantProductIds"] as? [Any])?
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !orderedIds.isEmpty else { return nil }

        let projections = (document["variants"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var projectionByProductId: [String: [String: Any]] = [:]
        for projection in projections {
            guard let productId = projection["productId"] as? String else { continue }
            projectionByProductId[productId] = projection
        }

        let defaultProductId = (document["defaultVariantProductId"] as? String) ?? ""

        var variants: [PPAccessoryVariant] = []
        for (index, productId) in orderedIds.enumerated() {
            let projection = projectionByProductId[productId]
            // Colour identity comes from the member product when it is loaded,
            // and from the family projection otherwise. Both are written by the
            // same server command, so they agree.
            let colorMap = products[productId]?.variantColorDictionary
                ?? (projection?["color"] as? [String: Any])
            guard let color = PPAccessoryVariantColor(dictionary: colorMap) else { continue }

            let product = products[productId]
            let sortOrder = (projection?["sortOrder"] as? NSNumber)?.intValue
                ?? product?.variantSortOrder
                ?? index
            let archived = (projection?["isArchived"] as? Bool) ?? product?.isArchived ?? false

            variants.append(PPAccessoryVariant(
                productId: productId,
                color: color,
                sortOrder: sortOrder,
                isArchived: archived,
                isDefault: productId == defaultProductId,
                sku: product?.sku ?? (projection?["sku"] as? String) ?? "",
                barcode: product?.barcode ?? (projection?["barcode"] as? String) ?? "",
                primaryImageURL: product.flatMap { PetAccessory.firstImageURL(for: $0)?.absoluteString }
                    ?? (projection?["primaryImageURL"] as? String) ?? "",
                quantity: product?.quantity ?? 0,
                retailPrice: (product?.hasResolvedSellingPrice == true) ? product?.finalPrice : nil,
                wholesalePrice: product?.wholesalePrice,
                hasResolvedRetailPrice: product?.hasResolvedSellingPrice ?? false,
                showInAppMarket: product?.showInAppMarket ?? false,
                revision: product?.revision ?? 0,
                media: (product?.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) }
            ))
        }
        guard !variants.isEmpty else { return nil }

        return PPAccessoryVariantFamily(
            familyId: documentID,
            name: (document["name"] as? String) ?? "",
            nameEn: (document["nameEn"] as? String) ?? "",
            desc: (document["desc"] as? String) ?? "",
            descEn: (document["descEn"] as? String) ?? "",
            accessKindType: (document["accessKindType"] as? NSNumber)?.intValue ?? 1,
            accessoryCategoryID: (document["AccessoryCategoryID"] as? String) ?? "",
            petMainCategoryID: (document["petMainCategoryID"] as? NSNumber)?.intValue ?? 0,
            petSubCategoryID: (document["petSubCategoryID"] as? NSNumber)?.intValue ?? 0,
            variantAxis: (document["variantAxis"] as? String) ?? PPAccessoryVariantContract.axisColor,
            variants: variants,
            defaultVariantProductId: defaultProductId,
            active: (document["active"] as? Bool) ?? true,
            isArchived: (document["isArchived"] as? Bool) ?? false,
            revision: (document["revision"] as? NSNumber)?.intValue ?? 0,
            isLegacySingleVariant: false
        )
    }

    /// Legacy adapter.
    ///
    /// Presents a product that has never been grouped as a one-colour family so
    /// the editor keeps a single code path. The synthetic colour is a
    /// placeholder: `hasServerColorIdentity` is false, and the operator must
    /// name the colour before the family can be saved. Nothing is written to
    /// the product until they do.
    @objc public static func legacySingleVariant(from accessory: PetAccessory) -> PPAccessoryVariantFamily {
        let placeholder = PPAccessoryVariantColor(
            identifier: "",
            nameAr: "",
            nameEn: "",
            hex: "#CCCCCC"
        )
        let existing = accessory.variantColorDictionary.flatMap { PPAccessoryVariantColor(dictionary: $0) }

        let variant = PPAccessoryVariant(
            productId: accessory.accessoryID,
            color: existing ?? placeholder,
            sortOrder: 0,
            isArchived: accessory.isArchived,
            isDefault: true,
            sku: accessory.sku ?? "",
            barcode: accessory.barcode ?? "",
            primaryImageURL: PetAccessory.firstImageURL(for: accessory)?.absoluteString ?? "",
            quantity: accessory.quantity,
            retailPrice: accessory.hasResolvedSellingPrice ? accessory.finalPrice : nil,
            wholesalePrice: accessory.wholesalePrice,
            hasResolvedRetailPrice: accessory.hasResolvedSellingPrice,
            showInAppMarket: accessory.showInAppMarket,
            revision: accessory.revision,
            media: (accessory.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) }
        )

        return PPAccessoryVariantFamily(
            familyId: accessory.productFamilyId ?? "",
            name: accessory.name ?? "",
            nameEn: accessory.nameEn ?? "",
            desc: accessory.desc ?? "",
            descEn: accessory.descEn ?? "",
            accessKindType: Int(accessory.accessKindType.rawValue),
            accessoryCategoryID: accessory.catalogCategoryIdentifier ?? "",
            petMainCategoryID: accessory.petMainCategoryID,
            petSubCategoryID: accessory.petSubCategoryID,
            variants: [variant],
            defaultVariantProductId: accessory.accessoryID,
            active: accessory.active,
            revision: 0,
            isLegacySingleVariant: (accessory.productFamilyId ?? "").isEmpty
        )
    }

    // MARK: Derived state

    @objc public var activeVariants: [PPAccessoryVariant] { variants.filter { !$0.isArchived } }
    @objc public var variantCount: Int { variants.count }
    @objc public var activeVariantCount: Int { activeVariants.count }

    /// Family availability is a projection only. Physical stock stays keyed on
    /// branch plus product id; never treat this as an authority.
    @objc public var totalAvailableQuantity: Int {
        activeVariants.reduce(0) { $0 + $1.quantity }
    }

    @objc public var defaultVariant: PPAccessoryVariant? {
        variants.first { $0.productId == defaultVariantProductId }
    }

    @objc public var heroImageURL: String {
        defaultVariant?.primaryImageURL
            ?? activeVariants.first?.primaryImageURL
            ?? variants.first?.primaryImageURL
            ?? ""
    }

    @objc public func variant(forProductId productId: String) -> PPAccessoryVariant? {
        variants.first { $0.productId == productId }
    }

    /// Resolves a scanned or typed code to exactly one colour.
    ///
    /// Exact match on barcode then SKU, case-insensitively. Returns nil when the
    /// code is ambiguous, so a caller can surface a disambiguation state instead
    /// of silently selling the first match.
    @objc public func variant(forExactCode code: String) -> PPAccessoryVariant? {
        let needle = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        for keyPath in [\PPAccessoryVariant.barcode, \PPAccessoryVariant.sku] {
            let matches = variants.filter { $0[keyPath: keyPath].lowercased() == needle }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        return nil
    }

    // MARK: Validation

    /// Mirrors the server invariants so the operator is told before a round
    /// trip. The server remains authoritative; this never replaces it.
    @objc public func validationMessages() -> [String] {
        var messages: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(Language.get("Variant_Error_FamilyName", alter: "اسم المنتج مطلوب."))
        }
        if variants.isEmpty {
            messages.append(Language.get("Variant_Error_NoVariants", alter: "أضف لونًا واحدًا على الأقل."))
        }
        if variants.count > PPAccessoryVariantContract.maxVariantsPerFamily {
            let template = Language.get("Variant_Error_TooMany", alter: "الحد الأقصى %@ لون.")
            messages.append(String(format: template, NSNumber(value: PPAccessoryVariantContract.maxVariantsPerFamily)))
        }
        if accessKindType == PPAccessoryVariantContract.livePetKindType {
            messages.append(Language.get("Variant_Error_LivePet", alter: "الحيوانات الحية لا تدعم الألوان المتعددة."))
        }
        if activeVariants.isEmpty && !variants.isEmpty {
            messages.append(Language.get("Variant_Error_AllArchived", alter: "يجب أن يبقى لون واحد نشطًا."))
        }

        for variant in variants {
            if let message = variant.color.validationMessage {
                messages.append("\(variant.color.accessibilityName.isEmpty ? variant.productId : variant.color.accessibilityName): \(message)")
            }
        }

        messages.append(contentsOf: duplicateMessages())

        guard let resolvedDefault = defaultVariant else {
            messages.append(Language.get("Variant_Error_DefaultMissing", alter: "اختر اللون الافتراضي."))
            return messages
        }
        if resolvedDefault.isArchived {
            messages.append(Language.get("Variant_Error_DefaultArchived", alter: "اللون الافتراضي مؤرشف. اختر لونًا نشطًا."))
        }
        // Public visibility is normalized atomically by the family callable.
        // Do not block a re-default here based on the pre-transaction listing
        // state; doing so would recreate the old client-side choreography.
        for variant in variants where variant.isArchived && variant.quantity > 0 {
            let template = Language.get(
                "Variant_Error_ArchivedWithStock",
                alter: "اللون %@ لا يزال يحتوي على مخزون ولا يمكن أرشفته."
            )
            messages.append(String(format: template, variant.color.accessibilityName))
        }

        return messages
    }

    private func duplicateMessages() -> [String] {
        var messages: [String] = []
        var seenColors: Set<String> = []
        var seenSkus: [String: String] = [:]
        var seenBarcodes: [String: String] = [:]

        for variant in variants {
            if !variant.color.identifier.isEmpty {
                if seenColors.contains(variant.color.identifier) {
                    let template = Language.get("Variant_Error_DuplicateColor", alter: "اللون %@ مستخدم أكثر من مرة.")
                    messages.append(String(format: template, variant.color.accessibilityName))
                }
                seenColors.insert(variant.color.identifier)
            }

            let sku = variant.sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !sku.isEmpty {
                if let owner = seenSkus[sku] {
                    let template = Language.get("Variant_Error_DuplicateSku", alter: "رمز SKU مكرر بين %@ و %@.")
                    messages.append(String(format: template, owner, variant.color.accessibilityName))
                }
                seenSkus[sku] = variant.color.accessibilityName
            }

            let barcode = variant.barcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !barcode.isEmpty {
                if let owner = seenBarcodes[barcode] {
                    let template = Language.get("Variant_Error_DuplicateBarcode", alter: "الباركود مكرر بين %@ و %@.")
                    messages.append(String(format: template, owner, variant.color.accessibilityName))
                }
                seenBarcodes[barcode] = variant.color.accessibilityName
            }
        }
        return messages
    }

    @objc public var isValid: Bool { validationMessages().isEmpty }

    // MARK: Request building

    /// Builds the full callable envelope.
    ///
    /// `create` for a family that does not exist on the server yet, `update`
    /// otherwise. `expectedFamilyRevision` is mandatory on update, and the
    /// per-variant revisions let a concurrent catalog edit be reported instead
    /// of overwritten.
    @objc public func commandEnvelope(commandId: String) -> [String: Any] {
        let isCreate = familyId.isEmpty || isLegacySingleVariant
        var envelope: [String: Any] = [
            "contractVersion": PPAccessoryVariantContract.contractVersion,
            "commandId": commandId,
            "action": isCreate ? "create" : "update",
            "payload": payload(),
        ]
        if !isCreate {
            envelope["familyId"] = familyId
            envelope["expectedFamilyRevision"] = revision
        }
        var expectedVariantRevisions: [String: Int] = [:]
        for variant in variants where variant.revision > 0 {
            expectedVariantRevisions[variant.productId] = variant.revision
        }
        if !expectedVariantRevisions.isEmpty {
            envelope["expectedVariantRevisions"] = expectedVariantRevisions
        }
        return envelope
    }

    @objc public func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "name": name,
            "accessKindType": accessKindType,
            "variantAxis": variantAxis,
            "variants": variants.enumerated().map { index, variant -> [String: Any] in
                var entry = variant.payload()
                entry["sortOrder"] = index
                return entry
            },
            "defaultVariantProductId": defaultVariantProductId,
            "active": active,
        ]
        // The callable rejects unknown keys, so only send an optional field when
        // it carries a value rather than padding the payload with empties.
        if !nameEn.isEmpty { payload["nameEn"] = nameEn }
        if !desc.isEmpty { payload["desc"] = desc }
        if !descEn.isEmpty { payload["descEn"] = descEn }
        if !accessoryCategoryID.isEmpty { payload["AccessoryCategoryID"] = accessoryCategoryID }
        if petMainCategoryID > 0 { payload["petMainCategoryID"] = petMainCategoryID }
        if petSubCategoryID > 0 { payload["petSubCategoryID"] = petSubCategoryID }
        return payload
    }

    // MARK: Dirty state

    /// Field-level comparison against a loaded baseline.
    ///
    /// The editor only has one coarse `hasUnsavedChanges` flag, so a variant
    /// workspace cannot rely on it. This gives an exact answer and avoids
    /// sending a command when nothing actually changed.
    @objc public func hasChanges(comparedTo baseline: PPAccessoryVariantFamily?) -> Bool {
        guard let baseline else { return true }
        if name != baseline.name
            || nameEn != baseline.nameEn
            || desc != baseline.desc
            || descEn != baseline.descEn
            || accessoryCategoryID != baseline.accessoryCategoryID
            || petMainCategoryID != baseline.petMainCategoryID
            || petSubCategoryID != baseline.petSubCategoryID
            || defaultVariantProductId != baseline.defaultVariantProductId
            || active != baseline.active
            || variants.count != baseline.variants.count {
            return true
        }
        for (index, variant) in variants.enumerated() {
            if !variant.isEqual(baseline.variants[index]) { return true }
        }
        return false
    }

    /// Product ids whose variant identity changed, for a targeted refresh.
    @objc public func changedProductIds(comparedTo baseline: PPAccessoryVariantFamily?) -> [String] {
        guard let baseline else { return variants.map(\.productId) }
        var baselineById: [String: PPAccessoryVariant] = [:]
        for variant in baseline.variants { baselineById[variant.productId] = variant }

        var changed: [String] = []
        for variant in variants {
            guard let previous = baselineById[variant.productId] else {
                changed.append(variant.productId)
                continue
            }
            if !variant.isEqual(previous) { changed.append(variant.productId) }
        }
        // A product removed from the family is also affected: the server clears
        // its variant identity and it reverts to a standalone product.
        let currentIds = Set(variants.map(\.productId))
        for variant in baseline.variants where !currentIds.contains(variant.productId) {
            changed.append(variant.productId)
        }
        return changed
    }

    /// Deep copy, so a workspace can be edited and discarded without mutating
    /// the loaded baseline.
    @objc public func copyForEditing() -> PPAccessoryVariantFamily {
        PPAccessoryVariantFamily(
            familyId: familyId,
            name: name,
            nameEn: nameEn,
            desc: desc,
            descEn: descEn,
            accessKindType: accessKindType,
            accessoryCategoryID: accessoryCategoryID,
            petMainCategoryID: petMainCategoryID,
            petSubCategoryID: petSubCategoryID,
            variantAxis: variantAxis,
            variants: variants.map { variant in
                PPAccessoryVariant(
                    productId: variant.productId,
                    color: PPAccessoryVariantColor(
                        identifier: variant.color.identifier,
                        nameAr: variant.color.nameAr,
                        nameEn: variant.color.nameEn,
                        hex: variant.color.hex
                    ),
                    sortOrder: variant.sortOrder,
                    isArchived: variant.isArchived,
                    isDefault: variant.isDefault,
                    sku: variant.sku,
                    barcode: variant.barcode,
                    primaryImageURL: variant.primaryImageURL,
                    quantity: variant.quantity,
                    retailPrice: variant.retailPrice,
                    wholesalePrice: variant.wholesalePrice,
                    hasResolvedRetailPrice: variant.hasResolvedRetailPrice,
                    showInAppMarket: variant.showInAppMarket,
                    revision: variant.revision,
                    media: variant.media
                )
            },
            defaultVariantProductId: defaultVariantProductId,
            active: active,
            isArchived: isArchived,
            revision: revision,
            isLegacySingleVariant: isLegacySingleVariant
        )
    }
}
