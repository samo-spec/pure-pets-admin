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
    /// Legacy envelope version (color-only).
    @objc public static let contractVersionLegacy = 2
    /// Generic envelope version (options + combinations).
    @objc public static let contractVersionGeneric = 3
    /// Default envelope version for legacy color families.
    @objc public static let contractVersion = 2
    /// Only supported variant axis for legacy envelope.
    @objc public static let axisColor = "color"
    /// Server bound; a family cannot exceed this, so one transaction always suffices.
    @objc public static let maxVariantsPerFamily = 40
    /// Option axes bound matching Infra productOptionsDomain.js
    @objc public static let maxOptionsPerFamily = 3
    /// Option values bound per option axis matching Infra productOptionsDomain.js
    @objc public static let maxValuesPerOption = 40
    /// Schema versions.
    @objc public static let variantSchemaVersionLegacy = 1
    @objc public static let variantSchemaVersionGeneric = 2
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

    @objc public convenience init(optionValue: PPAccessoryOptionValue) {
        self.init(
            identifier: optionValue.id,
            nameAr: optionValue.nameAr.isEmpty ? optionValue.canonicalValue : optionValue.nameAr,
            nameEn: optionValue.nameEn.isEmpty ? optionValue.canonicalValue : optionValue.nameEn,
            hex: optionValue.hex ?? "#7F7F7F"
        )
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

    @objc public static let standardNeutral = PPAccessoryVariantColor(
        identifier: "standard",
        nameAr: "افتراضي",
        nameEn: "Standard",
        hex: "#8E8E93"
    )

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

    static func string(_ value: Any?) -> String {
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

    @objc public static func color(fromHex hex: String) -> UIColor? {
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

// MARK: - Option Value

/// A single value for an option definition (e.g. "Black", "S", "500g").
/// Conforms to Infra productOptionsDomain.js:
/// { id, canonicalValue, displayName: { ar, en }, sortOrder, metadata: { hex, unit } }
@objc public final class PPAccessoryOptionValue: NSObject, @unchecked Sendable, Identifiable {
    @objc public let id: String
    @objc public var canonicalValue: String
    @objc public var nameAr: String
    @objc public var nameEn: String
    @objc public var sortOrder: Int
    @objc public var hex: String?
    @objc public var unit: String?

    @objc public init(
        id: String,
        canonicalValue: String,
        nameAr: String,
        nameEn: String,
        sortOrder: Int = 0,
        hex: String? = nil,
        unit: String? = nil
    ) {
        self.id = PPAccessoryOptionValue.normalizedIdentifier(id)
        self.canonicalValue = canonicalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = max(0, sortOrder)
        self.hex = hex.flatMap { PPAccessoryOptionValue.normalizedHex($0) }
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        super.init()
    }

    @objc public convenience init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let id = PPAccessoryVariantColor.string(dictionary["id"])
        guard !id.isEmpty else { return nil }
        let canonicalValue = PPAccessoryVariantColor.string(dictionary["canonicalValue"])
        let displayName = dictionary["displayName"] as? [String: Any]
        let nameAr = PPAccessoryVariantColor.string(displayName?["ar"])
        let nameEn = PPAccessoryVariantColor.string(displayName?["en"])
        let sortOrder = (dictionary["sortOrder"] as? NSNumber)?.intValue ?? 0
        let metadata = dictionary["metadata"] as? [String: Any]
        let hex = metadata?["hex"] as? String
        let unit = metadata?["unit"] as? String
        self.init(
            id: id,
            canonicalValue: canonicalValue.isEmpty ? (nameEn.isEmpty ? id : nameEn) : canonicalValue,
            nameAr: nameAr.isEmpty ? (canonicalValue.isEmpty ? id : canonicalValue) : nameAr,
            nameEn: nameEn.isEmpty ? (canonicalValue.isEmpty ? id : canonicalValue) : nameEn,
            sortOrder: sortOrder,
            hex: hex,
            unit: unit
        )
    }

    @objc public func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "canonicalValue": canonicalValue.isEmpty ? (nameEn.isEmpty ? id : nameEn) : canonicalValue,
            "displayName": [
                "ar": nameAr.isEmpty ? (canonicalValue.isEmpty ? id : canonicalValue) : nameAr,
                "en": nameEn.isEmpty ? (canonicalValue.isEmpty ? id : canonicalValue) : nameEn
            ],
            "sortOrder": sortOrder
        ]
        var metadata: [String: Any] = [:]
        if let hex, !hex.isEmpty { metadata["hex"] = hex }
        if let unit, !unit.isEmpty { metadata["unit"] = unit }
        if !metadata.isEmpty { payload["metadata"] = metadata }
        return payload
    }

    @objc public var localizedName: String {
        let raw: String
        if Language.isRTL() {
            raw = nameAr.isEmpty ? (nameEn.isEmpty ? canonicalValue : nameEn) : nameAr
        } else {
            raw = nameEn.isEmpty ? (nameAr.isEmpty ? canonicalValue : nameAr) : nameEn
        }
        return PPAccessoryOptionValue.formatSizeNameWithLetter(
            base: raw,
            canonicalValue: canonicalValue,
            id: id,
            nameAr: nameAr,
            nameEn: nameEn
        )
    }

    /// Detects canonical size code (e.g. "S", "M", "L", "XL", "XS", "2XL") from tokens.
    @objc public static func detectSizeCode(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let upper = trimmed.uppercased()

        if ["XXS", "XS", "S", "M", "L", "XL", "2XL", "XXL", "3XL", "XXXL", "4XL", "XXXXL"].contains(upper) {
            if upper == "XXL" { return "2XL" }
            if upper == "XXXL" { return "3XL" }
            if upper == "XXXXL" { return "4XL" }
            return upper
        }

        if upper == "DOUBLE EXTRA SMALL" { return "XXS" }
        if upper == "EXTRA SMALL" || upper == "EXTRA-SMALL" { return "XS" }
        if upper == "SMALL" { return "S" }
        if upper == "MEDIUM" { return "M" }
        if upper == "LARGE" { return "L" }
        if upper == "EXTRA LARGE" || upper == "EXTRA-LARGE" { return "XL" }
        if upper == "2X LARGE" || upper == "2X-LARGE" { return "2XL" }
        if upper == "3X LARGE" || upper == "3X-LARGE" { return "3XL" }
        if upper == "4X LARGE" || upper == "4X-LARGE" { return "4XL" }

        if trimmed == "صغير جداً جداً" { return "XXS" }
        if trimmed == "صغير جداً" { return "XS" }
        if trimmed == "صغير" { return "S" }
        if trimmed == "وسط" || trimmed == "متوسط" { return "M" }
        if trimmed == "كبير" { return "L" }
        if trimmed == "كبير جداً" { return "XL" }

        if upper.contains("(XXS)") || upper.contains("-XXS") || upper.contains("• XXS") || upper.hasPrefix("XXS") { return "XXS" }
        if upper.contains("(XS)") || upper.contains("-XS") || upper.contains("• XS") || upper.hasPrefix("XS") { return "XS" }
        if upper.contains("(XL)") || upper.contains("-XL") || upper.contains("• XL") || upper.hasPrefix("XL") { return "XL" }
        if upper.contains("(2XL)") || upper.contains("-2XL") || upper.contains("• 2XL") || upper.hasPrefix("2XL") || upper.contains("XXL") { return "2XL" }
        if upper.contains("(3XL)") || upper.contains("-3XL") || upper.contains("• 3XL") || upper.hasPrefix("3XL") || upper.contains("XXXL") { return "3XL" }
        if upper.contains("(4XL)") || upper.contains("-4XL") || upper.contains("• 4XL") || upper.hasPrefix("4XL") || upper.contains("XXXXL") { return "4XL" }
        if upper.contains("(S)") || upper.contains("-S") || upper.contains("• S") || upper.hasPrefix("S •") || upper.hasPrefix("S-") { return "S" }
        if upper.contains("(M)") || upper.contains("-M") || upper.contains("• M") || upper.hasPrefix("M •") || upper.hasPrefix("M-") { return "M" }
        if upper.contains("(L)") || upper.contains("-L") || upper.contains("• L") || upper.hasPrefix("L •") || upper.hasPrefix("L-") { return "L" }

        return nil
    }

    /// Formats size titles with the size letter in front (e.g. "S • صغير", "L • كبير", "XL • كبير جداً").
    @objc public static func formatSizeNameWithLetter(
        base: String,
        canonicalValue: String,
        id: String,
        nameAr: String,
        nameEn: String
    ) -> String {
        let isAr = Language.isRTL()
        let detected = detectSizeCode(from: canonicalValue)
            ?? detectSizeCode(from: id)
            ?? detectSizeCode(from: nameEn)
            ?? detectSizeCode(from: nameAr)
            ?? detectSizeCode(from: base)

        guard let code = detected else {
            return base
        }

        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return isAr ? "\(code) • \(arabicBaseName(for: code))" : "\(code) • \(englishBaseName(for: code))"
        }

        let upper = trimmedBase.uppercased()
        if upper.hasPrefix("\(code) •") || upper.hasPrefix("\(code)•")
            || upper.hasPrefix("\(code) -") || upper.hasPrefix("\(code)-")
            || upper.hasPrefix("\(code) :") || upper.hasPrefix("\(code):")
            || (upper.hasPrefix("\(code) ") && !upper.contains("SMALL") && !upper.contains("LARGE")) {
            return trimmedBase
        }

        var cleanBase = trimmedBase
        let legacySuffixes = ["(\(code))", "( \(code) )", "-\(code)", "- \(code)"]
        for suffix in legacySuffixes {
            if cleanBase.hasSuffix(suffix) {
                cleanBase = String(cleanBase.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if isAr {
            let arWord: String
            if cleanBase.uppercased() == code || cleanBase.isEmpty {
                arWord = arabicBaseName(for: code)
            } else {
                arWord = cleanBase
            }
            return "\(code) • \(arWord)"
        } else {
            let enWord: String
            if cleanBase.uppercased() == code || cleanBase.isEmpty {
                enWord = englishBaseName(for: code)
            } else {
                enWord = cleanBase
            }
            return "\(code) • \(enWord)"
        }
    }

    private static func arabicBaseName(for code: String) -> String {
        switch code {
        case "XXS": return "صغير جداً جداً"
        case "XS": return "صغير جداً"
        case "S": return "صغير"
        case "M": return "وسط"
        case "L": return "كبير"
        case "XL": return "كبير جداً"
        case "2XL": return "كبير جداً"
        case "3XL": return "كبير جداً"
        case "4XL": return "كبير جداً"
        default: return code
        }
    }

    private static func englishBaseName(for code: String) -> String {
        switch code {
        case "XXS": return "Double Extra Small"
        case "XS": return "Extra Small"
        case "S": return "Small"
        case "M": return "Medium"
        case "L": return "Large"
        case "XL": return "Extra Large"
        case "2XL": return "2X Large"
        case "3XL": return "3X Large"
        case "4XL": return "4X Large"
        default: return code
        }
    }

    @objc public var accessibilityName: String {
        let name = localizedName
        if let unit, !unit.isEmpty {
            return "\(name) (\(unit))"
        }
        return name
    }

    @objc public var isColor: Bool {
        guard let hex = hex else { return false }
        return !hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc public var uiColor: UIColor? {
        guard let hex else { return nil }
        return PPAccessoryVariantColor.color(fromHex: hex)
    }

    @objc public var requiresContrastBorder: Bool {
        guard let uiColor else { return false }
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getWhite(&white, alpha: &alpha) else { return false }
        return white > 0.82 || alpha < 0.95
    }

    @objc public func asVariantColor() -> PPAccessoryVariantColor? {
        guard let hex = hex, !hex.isEmpty else { return nil }
        return PPAccessoryVariantColor(
            identifier: id,
            nameAr: nameAr.isEmpty ? canonicalValue : nameAr,
            nameEn: nameEn.isEmpty ? canonicalValue : nameEn,
            hex: hex
        )
    }

    @objc public static func fromVariantColor(_ color: PPAccessoryVariantColor, sortOrder: Int = 0) -> PPAccessoryOptionValue {
        PPAccessoryOptionValue(
            id: color.identifier,
            canonicalValue: color.identifier,
            nameAr: color.nameAr,
            nameEn: color.nameEn,
            sortOrder: sortOrder,
            hex: color.hex,
            unit: nil
        )
    }

    @objc public func toVariantColor() -> PPAccessoryVariantColor {
        PPAccessoryVariantColor(
            identifier: id,
            nameAr: nameAr.isEmpty ? canonicalValue : nameAr,
            nameEn: nameEn.isEmpty ? canonicalValue : nameEn,
            hex: hex ?? "#7F7F7F"
        )
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PPAccessoryOptionValue else { return false }
        return id == other.id
            && canonicalValue == other.canonicalValue
            && nameAr == other.nameAr
            && nameEn == other.nameEn
            && sortOrder == other.sortOrder
            && hex == other.hex
            && unit == other.unit
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(canonicalValue)
        hasher.combine(nameAr)
        hasher.combine(nameEn)
        hasher.combine(sortOrder)
        hasher.combine(hex)
        hasher.combine(unit)
        return hasher.finalize()
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedHex(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !candidate.isEmpty else { return nil }
        if !candidate.hasPrefix("#") { candidate = "#" + candidate }
        if candidate.count == 4 {
            let components = Array(candidate.dropFirst())
            candidate = "#" + components.map { "\($0)\($0)" }.joined()
        }
        guard candidate.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else { return nil }
        return candidate
    }

    @objc public static func derivedIdentifier(fromName name: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty || slug.range(of: "^[a-z0-9]", options: .regularExpression) == nil {
            slug = "opt-\(abs(name.hashValue % 100000))"
        }
        return String(slug.prefix(64))
    }
}

// MARK: - Option Definition

/// A single option axis (e.g. "Color", "Size", "Weight").
/// Conforms to Infra productOptionsDomain.js:
/// { id, key, displayName: { ar, en }, sortOrder, values: [ProductOptionValue] }
@objc public final class PPAccessoryOptionDefinition: NSObject, @unchecked Sendable, Identifiable {
    @objc public let id: String
    @objc public var key: String
    @objc public var nameAr: String
    @objc public var nameEn: String
    @objc public var values: [PPAccessoryOptionValue]
    @objc public var sortOrder: Int

    @objc public init(
        id: String,
        key: String,
        nameAr: String,
        nameEn: String,
        values: [PPAccessoryOptionValue] = [],
        sortOrder: Int = 0
    ) {
        self.id = PPAccessoryOptionDefinition.normalizedIdentifier(id)
        self.key = PPAccessoryOptionDefinition.normalizedIdentifier(key)
        self.nameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        self.values = values.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
        }
        self.sortOrder = max(0, sortOrder)
        super.init()
    }

    @objc public convenience init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let id = PPAccessoryVariantColor.string(dictionary["id"])
        guard !id.isEmpty else { return nil }
        let key = PPAccessoryVariantColor.string(dictionary["key"])
        let displayName = dictionary["displayName"] as? [String: Any]
        let nameAr = PPAccessoryVariantColor.string(displayName?["ar"])
        let nameEn = PPAccessoryVariantColor.string(displayName?["en"])
        let sortOrder = (dictionary["sortOrder"] as? NSNumber)?.intValue ?? 0
        let rawValues = (dictionary["values"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        let values = rawValues.compactMap { PPAccessoryOptionValue(dictionary: $0) }
        self.init(
            id: id,
            key: key.isEmpty ? id : key,
            nameAr: nameAr.isEmpty ? (nameEn.isEmpty ? key : nameEn) : nameAr,
            nameEn: nameEn.isEmpty ? (nameAr.isEmpty ? key : nameAr) : nameEn,
            values: values,
            sortOrder: sortOrder
        )
    }

    @objc public func payload() -> [String: Any] {
        [
            "id": id,
            "key": key,
            "displayName": [
                "ar": nameAr.isEmpty ? key : nameAr,
                "en": nameEn.isEmpty ? key : nameEn
            ],
            "sortOrder": sortOrder,
            "values": values.enumerated().map { index, val in
                var p = val.payload()
                p["sortOrder"] = index
                return p
            }
        ]
    }

    @objc public var localizedName: String {
        if Language.isRTL() {
            return nameAr.isEmpty ? (nameEn.isEmpty ? key : nameEn) : nameAr
        }
        return nameEn.isEmpty ? (nameAr.isEmpty ? key : nameAr) : nameEn
    }

    @objc public var isColorOption: Bool { key == "color" }
    @objc public var isSizeOption: Bool { key == "size" }
    @objc public var isWeightOption: Bool { key == "weight" }
    @objc public var isMaterialOption: Bool { key == "material" }
    @objc public var isFlavorOption: Bool { key == "flavor" }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PPAccessoryOptionDefinition else { return false }
        guard id == other.id
            && key == other.key
            && nameAr == other.nameAr
            && nameEn == other.nameEn
            && sortOrder == other.sortOrder
            && values.count == other.values.count else { return false }
        for (index, val) in values.enumerated() {
            if !val.isEqual(other.values[index]) { return false }
        }
        return true
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(key)
        hasher.combine(nameAr)
        hasher.combine(nameEn)
        hasher.combine(sortOrder)
        return hasher.finalize()
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Presets

    @objc public static func presetColor(values: [PPAccessoryOptionValue] = []) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: "color",
            key: "color",
            nameAr: "اللون",
            nameEn: "Color",
            values: values,
            sortOrder: 0
        )
    }

    @objc public static func presetSize(values: [PPAccessoryOptionValue] = []) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: "size",
            key: "size",
            nameAr: "المقاس",
            nameEn: "Size",
            values: values,
            sortOrder: 1
        )
    }

    @objc public static func presetWeight(values: [PPAccessoryOptionValue] = []) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: "weight",
            key: "weight",
            nameAr: "الوزن",
            nameEn: "Weight",
            values: values,
            sortOrder: 2
        )
    }

    @objc public static func presetMaterial(values: [PPAccessoryOptionValue] = []) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: "material",
            key: "material",
            nameAr: "المادة",
            nameEn: "Material",
            values: values,
            sortOrder: 2
        )
    }

    @objc public static func presetFlavor(values: [PPAccessoryOptionValue] = []) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: "flavor",
            key: "flavor",
            nameAr: "النكهة",
            nameEn: "Flavor",
            values: values,
            sortOrder: 2
        )
    }

    @objc public static func custom(
        id: String,
        key: String,
        nameAr: String,
        nameEn: String,
        values: [PPAccessoryOptionValue] = [],
        sortOrder: Int = 0
    ) -> PPAccessoryOptionDefinition {
        PPAccessoryOptionDefinition(
            id: id,
            key: key,
            nameAr: nameAr,
            nameEn: nameEn,
            values: values,
            sortOrder: sortOrder
        )
    }

    // MARK: - Standard Values Library

    @objc public static let standardSizes: [PPAccessoryOptionValue] = [
        PPAccessoryOptionValue(id: "xs", canonicalValue: "XS", nameAr: "XS • صغير جداً", nameEn: "XS • Extra Small", sortOrder: 0),
        PPAccessoryOptionValue(id: "s", canonicalValue: "S", nameAr: "S • صغير", nameEn: "S • Small", sortOrder: 1),
        PPAccessoryOptionValue(id: "m", canonicalValue: "M", nameAr: "M • وسط", nameEn: "M • Medium", sortOrder: 2),
        PPAccessoryOptionValue(id: "l", canonicalValue: "L", nameAr: "L • كبير", nameEn: "L • Large", sortOrder: 3),
        PPAccessoryOptionValue(id: "xl", canonicalValue: "XL", nameAr: "XL • كبير جداً", nameEn: "XL • Extra Large", sortOrder: 4),
        PPAccessoryOptionValue(id: "2xl", canonicalValue: "2XL", nameAr: "2XL • كبير جداً", nameEn: "2XL • 2X Large", sortOrder: 5),
    ]

    @objc public static let standardWeights: [PPAccessoryOptionValue] = [
        PPAccessoryOptionValue(id: "250g", canonicalValue: "250g", nameAr: "٢٥٠ جم", nameEn: "250g", sortOrder: 0, unit: "g"),
        PPAccessoryOptionValue(id: "500g", canonicalValue: "500g", nameAr: "٥٠٠ جم", nameEn: "500g", sortOrder: 1, unit: "g"),
        PPAccessoryOptionValue(id: "1kg", canonicalValue: "1kg", nameAr: "١ كجم", nameEn: "1kg", sortOrder: 2, unit: "kg"),
        PPAccessoryOptionValue(id: "2kg", canonicalValue: "2kg", nameAr: "٢ كجم", nameEn: "2kg", sortOrder: 3, unit: "kg"),
        PPAccessoryOptionValue(id: "5kg", canonicalValue: "5kg", nameAr: "٥ كجم", nameEn: "5kg", sortOrder: 4, unit: "kg"),
        PPAccessoryOptionValue(id: "10kg", canonicalValue: "10kg", nameAr: "١٠ كجم", nameEn: "10kg", sortOrder: 5, unit: "kg"),
        PPAccessoryOptionValue(id: "15kg", canonicalValue: "15kg", nameAr: "١٥ كجم", nameEn: "15kg", sortOrder: 6, unit: "kg"),
    ]

    /// Synthesizes a canonical "color" option definition from existing colour variants.
    @objc public static func synthesizeColorOption(fromVariants variants: [PPAccessoryVariant]) -> PPAccessoryOptionDefinition {
        var values: [PPAccessoryOptionValue] = []
        var seen: Set<String> = []
        for (index, variant) in variants.enumerated() {
            let colorId = variant.color.identifier
            guard !colorId.isEmpty, !seen.contains(colorId) else { continue }
            seen.insert(colorId)
            values.append(PPAccessoryOptionValue.fromVariantColor(variant.color, sortOrder: index))
        }
        return PPAccessoryOptionDefinition.presetColor(values: values)
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
    @objc public var selectedOptions: [String: String]
    @objc public var combinationKey: String

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
        media: [PPAccessoryVariantMedia] = [],
        selectedOptions: [String: String] = [:],
        combinationKey: String = ""
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
        if selectedOptions.isEmpty {
            self.selectedOptions = [PPAccessoryVariantContract.axisColor: color.identifier]
            self.combinationKey = "\(PPAccessoryVariantContract.axisColor)=\(color.identifier)"
        } else {
            self.selectedOptions = selectedOptions
            self.combinationKey = combinationKey.isEmpty
                ? selectedOptions.keys.sorted().map { "\($0)=\(selectedOptions[$0] ?? "")" }.joined(separator: "|")
                : combinationKey
        }
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
            media: (accessory.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) },
            selectedOptions: [PPAccessoryVariantContract.axisColor: color.identifier],
            combinationKey: "\(PPAccessoryVariantContract.axisColor)=\(color.identifier)"
        )
    }

    /// Payload entry the legacy callable expects (contractVersion: 2).
    @objc public func payload() -> [String: Any] {
        [
            "productId": productId,
            "color": color.payload(),
            "sortOrder": sortOrder,
            "isArchived": isArchived,
        ]
    }

    /// Payload entry the generic options callable expects (contractVersion: 3).
    @objc public func genericPayload() -> [String: Any] {
        return [
            "productId": productId,
            "selectedOptions": selectedOptions,
            "sortOrder": sortOrder,
            "isArchived": isArchived,
        ]
    }

    @objc public var isSellable: Bool { !isArchived }

    /// Refresh only the catalog record this editor just wrote. Other members
    /// retain their observed revisions so concurrent staff edits still conflict.
    func refreshingCatalog(from product: PetAccessory) -> PPAccessoryVariant {
        PPAccessoryVariant(productId: productId, color: color, sortOrder: sortOrder,
            isArchived: isArchived, isDefault: isDefault, sku: product.sku ?? "", barcode: product.barcode ?? "",
            primaryImageURL: PetAccessory.firstImageURL(for: product)?.absoluteString ?? "", quantity: product.quantity,
            retailPrice: product.hasResolvedSellingPrice ? product.finalPrice : nil, wholesalePrice: product.wholesalePrice,
            hasResolvedRetailPrice: product.hasResolvedSellingPrice, showInAppMarket: product.showInAppMarket,
            revision: product.revision, media: (product.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) },
            selectedOptions: selectedOptions, combinationKey: combinationKey)
    }

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
            && selectedOptions == other.selectedOptions
            && combinationKey == other.combinationKey
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
    @objc public var familyId: String
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
    @objc public var optionDefinitions: [PPAccessoryOptionDefinition]
    /// A schema-2 family stays on envelope 3 even when only Color remains.
    @objc public var schemaVersion: Int
    /// Family revision observed at load, required for an update.
    @objc public var revision: Int
    /// True when this is a synthetic wrapper around a product that has no
    /// family on the server. Determines whether a save is `create` or `update`.
    @objc public var isLegacySingleVariant: Bool

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
        isLegacySingleVariant: Bool = false,
        optionDefinitions: [PPAccessoryOptionDefinition] = [],
        schemaVersion: Int = 1
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
        self.schemaVersion = schemaVersion
        self.optionDefinitions = optionDefinitions.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
        }
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
            let color = PPAccessoryVariantColor(dictionary: colorMap) ?? .standardNeutral

            let product = products[productId]
            guard product != nil || projection != nil else { continue }

            let sortOrder = (projection?["sortOrder"] as? NSNumber)?.intValue
                ?? product?.variantSortOrder
                ?? index
            let archived = (projection?["isArchived"] as? Bool) ?? product?.isArchived ?? false

            let rawSelectedOptions = (projection?["selectedOptions"] as? [String: String])
                ?? ((projection?["selectedOptions"] as? [String: Any])?.compactMapValues { "\($0)" })
                ?? [:]
            let combKey = (projection?["combinationKey"] as? String) ?? ""

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
                media: (product?.imageURLsArray ?? []).map { PPAccessoryVariantMedia(remoteURL: $0) },
                selectedOptions: rawSelectedOptions,
                combinationKey: combKey
            ))
        }
        guard !variants.isEmpty else { return nil }

        let rawOptionDefs = (document["optionDefinitions"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var optionDefinitions = rawOptionDefs.compactMap { PPAccessoryOptionDefinition(dictionary: $0) }
        if optionDefinitions.isEmpty && !variants.isEmpty {
            let hasRealColors = variants.contains { !$0.color.identifier.isEmpty && $0.color.identifier != "standard" }
            if hasRealColors {
                optionDefinitions = [PPAccessoryOptionDefinition.synthesizeColorOption(fromVariants: variants)]
            }
        }

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
            isLegacySingleVariant: false,
            optionDefinitions: optionDefinitions,
            schemaVersion: (document["schemaVersion"] as? NSNumber)?.intValue ?? 1
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
            ?? activeVariants.first
            ?? variants.first
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

        if !hasGenericOptions {
            for variant in variants {
                if let message = variant.color.validationMessage {
                    messages.append("\(variant.color.accessibilityName.isEmpty ? variant.productId : variant.color.accessibilityName): \(message)")
                }
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

        var seen = Set<String>()
        return messages.filter { seen.insert($0).inserted }
    }

    /// Retained dimensions keep their existing values and sellable identity.
    func identityChangeMessage(comparedTo baseline: PPAccessoryVariantFamily?) -> String? {
        guard hasGenericOptions, let baseline, !baseline.familyId.isEmpty, !baseline.isLegacySingleVariant else { return nil }
        let retained = Set(optionDefinitions.map(\.id)).intersection(baseline.optionDefinitions.map(\.id))
        for variant in variants {
            guard let old = baseline.variant(forProductId: variant.productId) else { continue }
            for id in retained {
                if let before = old.selectedOptions[id], let after = variant.selectedOptions[id], before != after {
                    return Language.get("Options_Error_IdentityImmutable", alter: "لا يمكن تغيير قيمة خيار محفوظ لصنف موجود. أنشئ متغيرًا جديدًا للتوليفة الجديدة للحفاظ على المخزون والسجل.")
                }
            }
        }
        return nil
    }

    func optionRemovalMessage(id: String) -> String? {
        let remaining = optionDefinitions.filter { $0.id != id }
        if remaining.isEmpty {
            return Language.get("Options_Error_LastOption", alter: "احتفظ بخيار واحد على الأقل لهذه المجموعة.")
        }
        var keys = Set<String>()
        let remainingHasColor = remaining.contains { $0.isColorOption }
        let remainingHasGeneric = !remaining.filter { !$0.isColorOption }.isEmpty

        for variant in variants {
            var selection: [String: String] = [:]
            for definition in remaining {
                if let value = variant.selectedOptions[definition.id] ?? variant.selectedOptions[definition.key], !value.isEmpty {
                    selection[definition.id] = value
                } else if definition.isColorOption && !variant.color.identifier.isEmpty {
                    selection[definition.id] = variant.color.identifier
                }
            }
            let key: String
            if !remainingHasGeneric && remainingHasColor {
                key = variant.color.identifier.isEmpty ? (selection.values.first ?? "") : variant.color.identifier
            } else {
                key = Self.combinationKey(from: selection)
            }
            if !key.isEmpty && !keys.insert(key).inserted {
                return Language.get("Options_Error_RemoveCollapsesVariants", alter: "هذا الخيار يميّز بين أصناف موجودة. حذفه سيجعل توليفاتها متطابقة؛ احتفظ به لحماية مخزون كل صنف.")
            }
        }
        return nil
    }

    private func duplicateMessages() -> [String] {
        var messages: [String] = []
        var seenColors: Set<String> = []
        var seenSkus: [String: String] = [:]
        var seenBarcodes: [String: String] = [:]

        let isSingleAxisColor = !hasGenericOptions

        for variant in variants {
            if isSingleAxisColor && !variant.color.identifier.isEmpty {
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

        if hasGenericOptions {
            var seenCombinations: Set<String> = []
            for variant in variants {
                let complete = optionDefinitions.allSatisfy { definition in
                    definition.values.contains { $0.id == variant.selectedOptions[definition.id] }
                }
                let key = PPAccessoryVariantFamily.combinationKey(from: variant.selectedOptions)
                if complete && !key.isEmpty {
                    if seenCombinations.contains(key) {
                        messages.append(Language.get("Options_Error_Duplicate_Combination", alter: "توجد توليفة خيارات مكررة بين متغيرين. لكل متغير توليفة فريدة."))
                    }
                    seenCombinations.insert(key)
                }
            }
        }

        // Validate options
        if optionDefinitions.count > PPAccessoryVariantContract.maxOptionsPerFamily {
            let template = Language.get("Options_Error_TooMany", alter: "الحد الأقصى %@ خيارات.")
            messages.append(String(format: template, NSNumber(value: PPAccessoryVariantContract.maxOptionsPerFamily)))
        }
        var seenOptionKeys: Set<String> = []
        var seenOptionIds: Set<String> = []
        for option in optionDefinitions {
            if seenOptionIds.contains(option.id) || seenOptionKeys.contains(option.key) {
                messages.append(Language.get("Options_Error_Duplicate_Option", alter: "هذا الخيار مكرر."))
            }
            seenOptionIds.insert(option.id)
            seenOptionKeys.insert(option.key)

            if option.values.isEmpty {
                let template = Language.get("Options_Error_NoValues", alter: "الخيار %@ يحتاج إلى قيمة واحدة على الأقل.")
                messages.append(String(format: template, option.localizedName))
            }
            if option.values.count > PPAccessoryVariantContract.maxValuesPerOption {
                let template = Language.get("Options_Error_TooManyValues", alter: "الخيار %@ يتجاوز الحد الأقصى (%@ قيمة).")
                messages.append(String(format: template, option.localizedName, NSNumber(value: PPAccessoryVariantContract.maxValuesPerOption)))
            }

            var seenValueIds: Set<String> = []
            var seenCanonicals: Set<String> = []
            for value in option.values {
                if seenValueIds.contains(value.id) || seenCanonicals.contains(value.canonicalValue.lowercased()) {
                    let template = Language.get("Options_Error_Duplicate_Value", alter: "القيمة %@ مكررة في الخيار %@.")
                    messages.append(String(format: template, value.localizedName, option.localizedName))
                }
                seenValueIds.insert(value.id)
                seenCanonicals.insert(value.canonicalValue.lowercased())

                if option.isColorOption && (value.hex == nil || value.hex?.isEmpty == true) {
                    let template = Language.get("Options_Error_ColorHexRequired", alter: "اللون %@ يحتاج إلى رمز لون صالح.")
                    messages.append(String(format: template, value.localizedName))
                }
            }
        }

        if hasGenericOptions {
            let activeDefs = optionDefinitions.filter { !$0.values.isEmpty }
            for variant in variants {
                for def in activeDefs {
                    let valId = variant.selectedOptions[def.id] ?? variant.selectedOptions[def.key]
                    if valId == nil || !def.values.contains(where: { $0.id == valId }) {
                        let template = Language.get("Options_Error_Incomplete_Variant", alter: "المتغير %@: اختر قيمة للخيار %@.")
                        let variantName = variant.color.localizedName.isEmpty
                            ? (variant.sku.isEmpty ? variant.productId : variant.sku)
                            : variant.color.localizedName
                        messages.append(String(format: template, variantName, def.localizedName))
                    }
                }
            }
        }

        return messages
    }

    /// Canonicalize IDs without guessing between sizes or reassigning a removed
    /// value. A sole new value is unambiguous; multiple choices require an
    /// explicit selection in the option card before saving.
    @objc public func autoBindMissingOptionSelections() {
        guard !optionDefinitions.isEmpty, !variants.isEmpty else { return }

        for variant in variants {
            var selected: [String: String] = [:]
            for def in optionDefinitions {
                if let value = variant.selectedOptions[def.id] ?? variant.selectedOptions[def.key], !value.isEmpty {
                    selected[def.id] = value
                } else if def.isColorOption && def.values.contains(where: { $0.id == variant.color.identifier }) {
                    selected[def.id] = variant.color.identifier
                } else if def.values.count == 1 {
                    selected[def.id] = def.values[0].id
                }
            }

            variant.selectedOptions = selected
            variant.combinationKey = PPAccessoryVariantFamily.combinationKey(from: selected)
        }
    }

    @objc public var isValid: Bool { validationMessages().isEmpty }

    @objc public var hasGenericOptions: Bool {
        if schemaVersion >= 2 { return true }
        if optionDefinitions.count > 1 { return true }
        if let first = optionDefinitions.first, first.key != PPAccessoryVariantContract.axisColor { return true }
        return false
    }

    // MARK: Request building

    /// Builds the full callable envelope.
    ///
    /// `create` for a family that does not exist on the server yet, `update`
    /// otherwise. `expectedFamilyRevision` is mandatory on update, and the
    /// per-variant revisions let a concurrent catalog edit be reported instead
    /// of overwritten.
    @objc public func commandEnvelope(commandId: String) -> [String: Any] {
        let isCreate = familyId.isEmpty || isLegacySingleVariant
        let contractVer = hasGenericOptions ? PPAccessoryVariantContract.contractVersionGeneric : PPAccessoryVariantContract.contractVersionLegacy
        var envelope: [String: Any] = [
            "contractVersion": contractVer,
            "commandId": commandId,
            "action": isCreate ? "create" : "update",
            "payload": payload(contractVersion: contractVer),
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

    @objc public func payload(contractVersion: Int = PPAccessoryVariantContract.contractVersionLegacy) -> [String: Any] {
        let isGeneric = (contractVersion >= PPAccessoryVariantContract.contractVersionGeneric)
        var payload: [String: Any] = [
            "name": name,
            "accessKindType": accessKindType,
            "variantAxis": isGeneric ? (optionDefinitions.count == 1 ? optionDefinitions[0].key : "options") : variantAxis,
            "variants": variants.enumerated().map { index, variant -> [String: Any] in
                var entry = isGeneric ? variant.genericPayload() : variant.payload()
                entry["sortOrder"] = index
                return entry
            },
            "defaultVariantProductId": defaultVariantProductId,
            "active": active,
        ]
        if isGeneric && !optionDefinitions.isEmpty {
            payload["optionDefinitions"] = optionDefinitions.enumerated().map { index, def in
                var p = def.payload()
                p["sortOrder"] = index
                return p
            }
        }
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
            || variants.count != baseline.variants.count
            || optionDefinitions.count != baseline.optionDefinitions.count {
            return true
        }
        for (index, variant) in variants.enumerated() {
            if !variant.isEqual(baseline.variants[index]) { return true }
        }
        for (index, option) in optionDefinitions.enumerated() {
            if !option.isEqual(baseline.optionDefinitions[index]) { return true }
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
                    media: variant.media,
                    selectedOptions: variant.selectedOptions,
                    combinationKey: variant.combinationKey
                )
            },
            defaultVariantProductId: defaultVariantProductId,
            active: active,
            isArchived: isArchived,
            revision: revision,
            isLegacySingleVariant: isLegacySingleVariant,
            optionDefinitions: optionDefinitions.map { opt in
                PPAccessoryOptionDefinition(
                    id: opt.id,
                    key: opt.key,
                    nameAr: opt.nameAr,
                    nameEn: opt.nameEn,
                    values: opt.values.map { val in
                        PPAccessoryOptionValue(
                            id: val.id,
                            canonicalValue: val.canonicalValue,
                            nameAr: val.nameAr,
                            nameEn: val.nameEn,
                            sortOrder: val.sortOrder,
                            hex: val.hex,
                            unit: val.unit
                        )
                    },
                    sortOrder: opt.sortOrder
                )
            },
            schemaVersion: schemaVersion
        )
    }

    @objc public func deepCopy() -> PPAccessoryVariantFamily {
        copyForEditing()
    }

    /// Canonical combination key generator from a dictionary of selected options.
    @objc public static func combinationKey(from selectedOptions: [String: String]) -> String {
        selectedOptions.keys.sorted().map { "\($0)=\(selectedOptions[$0] ?? "")" }.joined(separator: "|")
    }
}

// MARK: - Matrix Models (Phase 6)

@objc public enum PPAccessoryCombinationStatus: Int {
    case unconfigured = 0
    case inStock = 1
    case outOfStock = 2
    case inactive = 3

    public var localizedName: String {
        switch self {
        case .unconfigured:
            return Language.get("Variant_Status_Unconfigured", alter: "غير مهيأ")
        case .inStock:
            return Language.get("Variant_Stock_InStock", alter: "متوفر")
        case .outOfStock:
            return Language.get("Variant_Stock_OutOfStock", alter: "نفد من المخزون")
        case .inactive:
            return Language.get("Variant_Status_Inactive", alter: "معطل")
        }
    }
}

/// One cell / combination in the product variant matrix.
/// Can be either an existing sellable variant or an unconfigured potential combination.
@objc public final class PPAccessoryMatrixCombination: NSObject, Identifiable, @unchecked Sendable {
    @objc public let combinationKey: String
    @objc public let selectedOptions: [String: String]
    @objc public let optionValues: [PPAccessoryOptionValue]
    @objc public let existingVariant: PPAccessoryVariant?
    @objc public let status: PPAccessoryCombinationStatus

    public var id: String { combinationKey }

    @objc public init(
        combinationKey: String,
        selectedOptions: [String: String],
        optionValues: [PPAccessoryOptionValue],
        existingVariant: PPAccessoryVariant?,
        status: PPAccessoryCombinationStatus
    ) {
        self.combinationKey = combinationKey
        self.selectedOptions = selectedOptions
        self.optionValues = optionValues
        self.existingVariant = existingVariant
        self.status = status
        super.init()
    }

    @objc public var productId: String? { existingVariant?.productId }
    @objc public var isCreated: Bool { existingVariant != nil }
    @objc public var isArchived: Bool { existingVariant?.isArchived ?? false }
    @objc public var isDefault: Bool { existingVariant?.isDefault ?? false }
    @objc public var quantity: Int { existingVariant?.quantity ?? 0 }
    @objc public var sku: String { existingVariant?.sku ?? "" }
    @objc public var barcode: String { existingVariant?.barcode ?? "" }
    @objc public var retailPrice: NSNumber? { existingVariant?.retailPrice }
    @objc public var wholesalePrice: NSNumber? { existingVariant?.wholesalePrice }
    @objc public var primaryImageURL: String { existingVariant?.primaryImageURL ?? "" }

    /// Localized title combining values in order (e.g. "أحمر / وسط" or "Red / M")
    @objc public var localizedTitle: String {
        if !optionValues.isEmpty {
            return optionValues.map(\.localizedName).joined(separator: " / ")
        }
        if let v = existingVariant {
            return v.color.localizedName
        }
        return combinationKey
    }

    /// Color swatch value if this combination contains a color
    @objc public var colorValue: PPAccessoryOptionValue? {
        optionValues.first(where: { $0.isColor })
    }

    /// Secondary option label (e.g. size or weight) when primary option is used for grouping
    @objc public var secondaryOptionsSummary: String {
        if optionValues.count > 1 {
            return optionValues.dropFirst().map(\.localizedName).joined(separator: " • ")
        }
        return localizedTitle
    }
}

/// A group of combinations, typically grouped by the primary option (e.g., Color).
@objc public final class PPAccessoryMatrixGroup: NSObject, Identifiable, @unchecked Sendable {
    @objc public let id: String
    @objc public let primaryValue: PPAccessoryOptionValue?
    @objc public let primaryDefinition: PPAccessoryOptionDefinition?
    @objc public let combinations: [PPAccessoryMatrixCombination]

    @objc public init(
        id: String,
        primaryValue: PPAccessoryOptionValue?,
        primaryDefinition: PPAccessoryOptionDefinition?,
        combinations: [PPAccessoryMatrixCombination]
    ) {
        self.id = id
        self.primaryValue = primaryValue
        self.primaryDefinition = primaryDefinition
        self.combinations = combinations
        super.init()
    }

    @objc public var totalStock: Int {
        combinations.reduce(0) { $0 + $1.quantity }
    }

    @objc public var configuredCount: Int {
        combinations.filter(\.isCreated).count
    }

    @objc public var totalCombinationsCount: Int {
        combinations.count
    }

    @objc public var activeVariantsCount: Int {
        combinations.filter { $0.isCreated && !$0.isArchived }.count
    }

    @objc public var localizedTitle: String {
        if let val = primaryValue {
            return val.localizedName
        }
        return Language.get("Variant_Matrix_AllVariants", alter: "كافة المتغيرات")
    }

    @objc public var colorValue: PPAccessoryOptionValue? {
        if primaryDefinition?.isColorOption == true {
            return primaryValue
        }
        return combinations.first?.colorValue
    }
}

// MARK: - Matrix Generation Extension

extension PPAccessoryVariantFamily {
    /// Generates all valid Cartesian combinations from `optionDefinitions` and correlates each
    /// with existing variants in the family.
    @objc public func generateMatrixCombinations() -> [PPAccessoryMatrixCombination] {
        let activeDefs = optionDefinitions.filter { !$0.values.isEmpty }
        guard !activeDefs.isEmpty else {
            // No options defined: present existing variants directly or single standalone
            return variants.map { variant in
                let status: PPAccessoryCombinationStatus = variant.isArchived ? .inactive : (variant.quantity > 0 ? .inStock : .outOfStock)
                return PPAccessoryMatrixCombination(
                    combinationKey: variant.combinationKey.isEmpty ? variant.productId : variant.combinationKey,
                    selectedOptions: variant.selectedOptions,
                    optionValues: [PPAccessoryOptionValue.fromVariantColor(variant.color)],
                    existingVariant: variant,
                    status: status
                )
            }
        }

        // Cartesian product of option values
        var valueCombinations: [[PPAccessoryOptionValue]] = [[]]
        for def in activeDefs {
            var next: [[PPAccessoryOptionValue]] = []
            for existing in valueCombinations {
                for val in def.values {
                    next.append(existing + [val])
                }
            }
            valueCombinations = next
        }

        var matchedVariantIds = Set<String>()
        var combinations: [PPAccessoryMatrixCombination] = []

        for values in valueCombinations {
            var selected: [String: String] = [:]
            for (idx, val) in values.enumerated() {
                if idx < activeDefs.count {
                    selected[activeDefs[idx].id] = val.id
                }
            }
            let key = PPAccessoryVariantFamily.combinationKey(from: selected)

            // Match with existing variant
            let matched = variants.first { v in
                if !v.combinationKey.isEmpty && v.combinationKey == key { return true }
                if !v.selectedOptions.isEmpty && v.selectedOptions == selected { return true }
                if activeDefs.count == 1 && activeDefs[0].isColorOption && v.color.identifier == values.first?.id {
                    return true
                }
                return false
            }

            if let matched {
                matchedVariantIds.insert(matched.productId)
                let status: PPAccessoryCombinationStatus = matched.isArchived
                    ? .inactive
                    : (matched.quantity > 0 ? .inStock : .outOfStock)
                combinations.append(PPAccessoryMatrixCombination(
                    combinationKey: key,
                    selectedOptions: selected,
                    optionValues: values,
                    existingVariant: matched,
                    status: status
                ))
            } else {
                combinations.append(PPAccessoryMatrixCombination(
                    combinationKey: key,
                    selectedOptions: selected,
                    optionValues: values,
                    existingVariant: nil,
                    status: .unconfigured
                ))
            }
        }

        // Safety: If any existing variant was not matched in the Cartesian product (e.g. legacy or custom combination),
        // include it so stocked/referenced variants are NEVER lost from view.
        for variant in variants where !matchedVariantIds.contains(variant.productId) {
            let status: PPAccessoryCombinationStatus = variant.isArchived
                ? .inactive
                : (variant.quantity > 0 ? .inStock : .outOfStock)
            combinations.append(PPAccessoryMatrixCombination(
                combinationKey: variant.combinationKey.isEmpty ? variant.productId : variant.combinationKey,
                selectedOptions: variant.selectedOptions,
                optionValues: [PPAccessoryOptionValue.fromVariantColor(variant.color)],
                existingVariant: variant,
                status: status
            ))
        }

        return combinations
    }

    /// Groups matrix combinations by the primary option (typically Option 1 / Color).
    @objc public func generateMatrixGroups() -> [PPAccessoryMatrixGroup] {
        let allCombinations = generateMatrixCombinations()
        let activeDefs = optionDefinitions.filter { !$0.values.isEmpty }

        guard activeDefs.count >= 2, let primaryDef = activeDefs.first else {
            // 0 or 1 option: wrap in a single unified group
            return [
                PPAccessoryMatrixGroup(
                    id: "all",
                    primaryValue: nil,
                    primaryDefinition: activeDefs.first,
                    combinations: allCombinations
                )
            ]
        }

        // 2+ options: group by primary option values
        var groups: [PPAccessoryMatrixGroup] = []
        for val in primaryDef.values {
            let matching = allCombinations.filter { comb in
                comb.selectedOptions[primaryDef.id] == val.id
            }
            if !matching.isEmpty {
                groups.append(PPAccessoryMatrixGroup(
                    id: val.id,
                    primaryValue: val,
                    primaryDefinition: primaryDef,
                    combinations: matching
                ))
            }
        }

        // Check for any unallocated combinations
        let groupedKeys = Set(groups.flatMap(\.combinations).map(\.combinationKey))
        let remaining = allCombinations.filter { !groupedKeys.contains($0.combinationKey) }
        if !remaining.isEmpty {
            groups.append(PPAccessoryMatrixGroup(
                id: "other",
                primaryValue: nil,
                primaryDefinition: nil,
                combinations: remaining
            ))
        }

        return groups
    }
}

// MARK: - Variant Dimension & Presentation Engine

@objc public enum PPAccessoryVariantDimensionType: Int, Sendable {
    case color
    case size
    case weight
    case flavor
    case material
    case custom
    case multiple

    public var sfSymbolName: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .size: return "ruler.fill"
        case .weight: return "scalemass.fill"
        case .flavor: return "fork.knife"
        case .material: return "cube.fill"
        case .custom, .multiple: return "square.stack.fill"
        }
    }

    public var outlineSymbolName: String {
        switch self {
        case .color: return "paintpalette"
        case .size: return "ruler"
        case .weight: return "scalemass"
        case .flavor: return "fork.knife"
        case .material: return "cube"
        case .custom, .multiple: return "square.stack"
        }
    }

    public var selectionTitle: String {
        switch self {
        case .color:
            return Language.get("POS_SelectColorVariant", alter: "اختر اللون")
        case .size:
            return Language.get("POS_SelectSizeVariant", alter: "اختر المقاس")
        case .weight:
            return Language.get("POS_SelectWeightVariant", alter: "اختر الوزن")
        case .flavor:
            return Language.get("POS_SelectFlavorVariant", alter: "اختر النكهة")
        case .material:
            return Language.get("POS_SelectMaterialVariant", alter: "اختر المادة")
        case .custom, .multiple:
            return Language.get("POS_SelectOptionVariant", alter: "اختر الخيار")
        }
    }

    public var countOptionsLabel: String {
        switch self {
        case .color:
            return Language.get("POS_VariantsCount", alter: "خيارات ألوان")
        case .size:
            return Language.get("POS_VariantsSizeCount", alter: "خيارات مقاس")
        case .weight:
            return Language.get("POS_VariantsWeightCount", alter: "خيارات وزن")
        case .flavor:
            return Language.get("POS_VariantsFlavorCount", alter: "خيارات نكهة")
        case .material:
            return Language.get("POS_VariantsMaterialCount", alter: "خيارات خامة")
        case .custom, .multiple:
            return Language.get("POS_VariantsGeneralCount", alter: "خيارات")
        }
    }

    public var shortCountFormat: String {
        switch self {
        case .color:
            return Language.get("Inventory_Family_ColourCount", alter: "%@ ألوان")
        case .size:
            return Language.get("Inventory_Family_SizeCount", alter: "%@ مقاسات")
        case .weight:
            return Language.get("Inventory_Family_WeightCount", alter: "%@ أوزان")
        case .flavor:
            return Language.get("Inventory_Family_FlavorCount", alter: "%@ نكهات")
        case .material:
            return Language.get("Inventory_Family_MaterialCount", alter: "%@ خامات")
        case .custom, .multiple:
            return Language.get("Inventory_Family_OptionCount", alter: "%@ خيارات")
        }
    }

    public var outOfStockBadgeText: String {
        switch self {
        case .color:
            return Language.get("Inventory_Family_HasOutOfStock", alter: "لون غير متوفر")
        case .size:
            return Language.get("Inventory_Family_HasOutOfStockSize", alter: "مقاس غير متوفر")
        case .weight:
            return Language.get("Inventory_Family_HasOutOfStockWeight", alter: "وزن غير متوفر")
        case .flavor:
            return Language.get("Inventory_Family_HasOutOfStockFlavor", alter: "نكهة غير متوفرة")
        case .material:
            return Language.get("Inventory_Family_HasOutOfStockMaterial", alter: "خامة غير متوفرة")
        case .custom, .multiple:
            return Language.get("Inventory_Family_HasOutOfStockOption", alter: "خيار غير متوفر")
        }
    }

    public var selectHint: String {
        switch self {
        case .color:
            return Language.get("Inventory_Family_SelectColour_Hint", alter: "يعرض سعر ومخزون وإجراءات هذا اللون")
        case .size:
            return Language.get("Inventory_Family_SelectSize_Hint", alter: "يعرض سعر ومخزون وإجراءات هذا المقاس")
        case .weight:
            return Language.get("Inventory_Family_SelectWeight_Hint", alter: "يعرض سعر ومخزون وإجراءات هذا الوزن")
        case .flavor, .material, .custom, .multiple:
            return Language.get("Inventory_Family_SelectOption_Hint", alter: "يعرض سعر ومخزون وإجراءات هذا الخيار")
        }
    }

    public var collapseHint: String {
        switch self {
        case .color:
            return Language.get("Inventory_Family_Collapse_Hint", alter: "طي الألوان")
        case .size:
            return Language.get("Inventory_Family_CollapseSize_Hint", alter: "طي المقاسات")
        case .weight:
            return Language.get("Inventory_Family_CollapseWeight_Hint", alter: "طي الأوزان")
        case .flavor, .material, .custom, .multiple:
            return Language.get("Inventory_Family_CollapseOption_Hint", alter: "طي الخيارات")
        }
    }

    public var expandHint: String {
        switch self {
        case .color:
            return Language.get("Inventory_Family_Expand_Hint", alter: "اختر لوناً لعرض سعره ومخزونه وإجراءاته")
        case .size:
            return Language.get("Inventory_Family_ExpandSize_Hint", alter: "اختر مقاساً لعرض سعره ومخزونه وإجراءاته")
        case .weight:
            return Language.get("Inventory_Family_ExpandWeight_Hint", alter: "اختر وزناً لعرض سعره ومخزونه وإجراءاته")
        case .flavor, .material, .custom, .multiple:
            return Language.get("Inventory_Family_ExpandOption_Hint", alter: "اختر خياراً لعرض سعره ومخزونه وإجراءاته")
        }
    }
}

// MARK: - PetAccessory Variant Dimension & Display Extensions

public extension PetAccessory {
    /// Resolved variant color model from `variantColorDictionary`.
    var pos_variantColor: PPAccessoryVariantColor? {
        guard let dict = variantColorDictionary else { return nil }
        return PPAccessoryVariantColor(dictionary: dict)
    }

    /// Color display name in the active language.
    var pos_variantColorName: String {
        pos_variantColor?.localizedName ?? ""
    }

    /// Returns true ONLY if this accessory represents a genuine color variant (not a dummy neutral or size).
    var pos_hasRealColor: Bool {
        guard let color = pos_variantColor else { return false }
        let id = color.identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty && id != "standard" && id != "default" && id != "neutral" else {
            return false
        }

        // If the color name indicates a size/weight/option rather than a color, it's not a real color.
        let nameAr = color.nameAr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let nameEn = color.nameEn.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let knownSizeTokens = ["صغير", "متوسط", "كبير", "xs", "s", "m", "l", "xl", "2xl", "3xl", "4xl", "small", "medium", "large", "free size"]
        let hasSizeInName = knownSizeTokens.contains { nameAr == $0 || nameEn == $0 || nameAr.hasPrefix($0 + " ") || nameEn.hasPrefix($0 + " ") || nameAr.contains(" " + $0) }

        let knownColorWords = ["أبيض", "ابيض", "اسود", "أسود", "احمر", "أحمر", "ازرق", "أزرق", "اخضر", "أخضر", "اصفر", "أصفر", "بني", "وردي", "برتقالي", "بنفسجي", "رمادي", "كحلي", "بيج", "ذهبي", "فضي", "white", "black", "red", "blue", "green", "yellow", "brown", "pink", "orange", "purple", "gray", "grey", "navy", "beige", "gold", "silver"]
        let hasRealColorWord = knownColorWords.contains { nameAr.contains($0) || nameEn.contains($0) || id.contains($0) }

        if hasSizeInName && !hasRealColorWord {
            return false
        }

        // Check hex: if standard neutral/white (#CCCCCC / #7F7F7F / #8E8E93 / #FFFFFF) and has no explicit color word
        let hex = color.hex.uppercased()
        if (hex == "#CCCCCC" || hex == "#7F7F7F" || hex == "#8E8E93" || hex == "#FFFFFF") && !hasRealColorWord {
            return false
        }

        return true
    }

    /// Detects the variant dimension type for this individual product.
    var pos_variantDimension: PPAccessoryVariantDimensionType {
        // 1. Check explicit variantAxis from backend / family
        if let axis = variantAxis?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !axis.isEmpty {
            switch axis {
            case "color", "colors", "اللون": return .color
            case "size", "sizes", "المقاس", "الحجم": return .size
            case "weight", "weights", "الوزن": return .weight
            case "flavor", "flavors", "flavour", "flavours", "النكهة", "الطعم": return .flavor
            case "material", "materials", "المادة", "الخامة": return .material
            default: break
            }
        }

        // 2. Check selectedOptionsSnapshot
        if let snapshot = selectedOptionsSnapshot, !snapshot.isEmpty {
            if snapshot.count > 1 { return .multiple }
            if let first = snapshot.first {
                let optKey = (first["optionKey"] as? String)?.lowercased() ?? ""
                if optKey.contains("size") || optKey.contains("مقاس") || optKey.contains("حجم") { return .size }
                if optKey.contains("weight") || optKey.contains("وزن") { return .weight }
                if optKey.contains("flavor") || optKey.contains("flavour") || optKey.contains("نكهة") { return .flavor }
                if optKey.contains("material") || optKey.contains("مادة") || optKey.contains("خامة") { return .material }
                if optKey.contains("color") || optKey.contains("لون") { return .color }
            }
        }

        // 3. Check selectedOptions dictionary keys
        if let options = selectedOptions, !options.isEmpty {
            if options.count > 1 { return .multiple }
            let keys = options.keys.map { $0.lowercased() }
            if keys.contains(where: { $0.contains("size") || $0.contains("مقاس") || $0.contains("حجم") }) { return .size }
            if keys.contains(where: { $0.contains("weight") || $0.contains("وزن") }) { return .weight }
            if keys.contains(where: { $0.contains("flavor") || $0.contains("flavour") || $0.contains("نكهة") }) { return .flavor }
            if keys.contains(where: { $0.contains("material") || $0.contains("مادة") || $0.contains("خامة") }) { return .material }
            if keys.contains(where: { $0.contains("color") || $0.contains("لون") }) { return .color }
        }

        // 4. Check variantCombinationKey
        if let combo = variantCombinationKey?.lowercased(), !combo.isEmpty {
            if combo.contains("size=") { return .size }
            if combo.contains("weight=") { return .weight }
            if combo.contains("flavor=") || combo.contains("flavour=") { return .flavor }
            if combo.contains("material=") { return .material }
            if combo.contains("color=") && !combo.contains("|") { return .color }
            if combo.contains("|") { return .multiple }
        }

        // 5. Genuine color check
        if pos_hasRealColor {
            return .color
        }

        // 6. Check size attribute on model
        if let s = size?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return .size
        }

        // 7. Check weightText or weight on model
        if let w = weightText?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            return .weight
        }
        if let wNum = weight, wNum.doubleValue > 0 {
            return .weight
        }

        // 8. Check SKU suffix for size or weight
        if let sku = sku?.uppercased() {
            let sizeSuffixes = ["-XS", "_XS", "-S", "_S", "-M", "_M", "-L", "_L", "-XL", "_XL", "-2XL", "_2XL", "-XXL", "_XXL", "-3XL", "_3XL", "-4XL", "_4XL"]
            if sizeSuffixes.contains(where: { sku.hasSuffix($0) }) {
                return .size
            }
            let weightSuffixes = ["-250G", "-500G", "-1KG", "-2KG", "-3KG", "-5KG", "-10KG", "-15KG", "-20KG"]
            if weightSuffixes.contains(where: { sku.hasSuffix($0) }) {
                return .weight
            }
        }

        // 9. Check color model names for size keywords
        if let color = pos_variantColor {
            let nameAr = color.nameAr.lowercased()
            let nameEn = color.nameEn.lowercased()
            let sizeKeywords = ["صغير", "متوسط", "كبير", "xs", "small", "medium", "large", "xl"]
            if sizeKeywords.contains(where: { nameAr.contains($0) || nameEn.contains($0) }) {
                return .size
            }
        }

        return belongsToVariantFamily ? .custom : .color
    }

    /// Formats standard size codes into localized, friendly names with size letter in front.
    static func formatStandardSize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let code = trimmed.uppercased()
        let isAr = Language.isRTL()
        switch code {
        case "XXS", "DOUBLE EXTRA SMALL":
            return isAr ? "XXS • صغير جداً جداً" : "XXS • Double Extra Small"
        case "XS", "EXTRA SMALL", "EXTRA-SMALL":
            return isAr ? "XS • صغير جداً" : "XS • Extra Small"
        case "S", "SMALL":
            return isAr ? "S • صغير" : "S • Small"
        case "M", "MEDIUM":
            return isAr ? "M • وسط" : "M • Medium"
        case "L", "LARGE":
            return isAr ? "L • كبير" : "L • Large"
        case "XL", "EXTRA LARGE", "EXTRA-LARGE":
            return isAr ? "XL • كبير جداً" : "XL • Extra Large"
        case "2XL", "XXL", "2X LARGE", "2X-LARGE":
            return isAr ? "2XL • كبير جداً" : "2XL • 2X Large"
        case "3XL", "XXXL", "3X LARGE", "3X-LARGE":
            return isAr ? "3XL • كبير جداً" : "3XL • 3X Large"
        case "4XL", "XXXXL":
            return isAr ? "4XL • كبير جداً" : "4XL • 4X Large"
        case "FREE", "FREE SIZE", "FREESIZE":
            return isAr ? "مقاس موحد" : "Free Size"
        default:
            if let detected = PPAccessoryOptionValue.detectSizeCode(from: trimmed) {
                return formatStandardSize(detected)
            }
            return trimmed
        }
    }

    /// Extracts short 1-4 character badge for chip/icon display (e.g. "XS", "S", "M", "L", "XL", "1kg").
    var pos_variantShortBadge: String {
        // From size property
        if let s = size?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            let upper = s.uppercased()
            if ["XS", "S", "M", "L", "XL", "2XL", "XXL", "3XL", "4XL"].contains(upper) {
                return upper == "XXL" ? "2XL" : upper
            }
        }

        // From SKU suffix
        if let sku = sku?.uppercased() {
            let patterns = [
                ("-4XL", "4XL"), ("-3XL", "3XL"), ("-2XL", "2XL"), ("-XXL", "2XL"),
                ("-XL", "XL"), ("-XS", "XS"), ("-S", "S"), ("-M", "M"), ("-L", "L"),
                ("_4XL", "4XL"), ("_3XL", "3XL"), ("_2XL", "2XL"), ("_XXL", "2XL"),
                ("_XL", "XL"), ("_XS", "XS"), ("_S", "S"), ("_M", "M"), ("_L", "L")
            ]
            for (suffix, badge) in patterns {
                if sku.hasSuffix(suffix) {
                    return badge
                }
            }
        }

        // From selectedOptions
        if let options = selectedOptions {
            for (k, v) in options {
                if k.lowercased().contains("size"), let strVal = v as? String {
                    let upper = strVal.uppercased()
                    if ["XS", "S", "M", "L", "XL", "2XL", "XXL", "3XL", "4XL"].contains(upper) {
                        return upper == "XXL" ? "2XL" : upper
                    }
                }
            }
        }

        // From combinationKey
        if let combo = variantCombinationKey?.uppercased() {
            for part in combo.components(separatedBy: "|") {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 && kv[0].contains("SIZE") {
                    let val = kv[1]
                    if ["XS", "S", "M", "L", "XL", "2XL", "XXL", "3XL", "4XL"].contains(val) {
                        return val == "XXL" ? "2XL" : val
                    }
                }
            }
        }

        // From variantColor name if it's a size code
        if let color = pos_variantColor {
            let upper = color.identifier.uppercased()
            if ["XS", "S", "M", "L", "XL", "2XL", "XXL", "3XL", "4XL"].contains(upper) {
                return upper == "XXL" ? "2XL" : upper
            }
        }

        return ""
    }

    /// Formatted, localized smart variant description (e.g. "اللون: أزرق • المقاس: M" or "Color: Blue • Size: M").
    /// Explicitly prefixes dimension names (Color / Size / Weight / etc.) so receipts, invoices, and POS line items
    /// are unmistakable and crystal clear for customers and staff alike.
    var pos_smartVariantDescription: String? {
        let isAr = Language.isRTL()
        var parts: [String] = []

        // 1. From selectedOptionsSnapshot (structured modern options)
        if let snapshot = selectedOptionsSnapshot, !snapshot.isEmpty {
            for option in snapshot {
                let optKey = (option["optionKey"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // Resolve option label
                var optLabel = ""
                if let nameDict = option["optionName"] as? [String: Any] {
                    let langKey = isAr ? "ar" : "en"
                    optLabel = (nameDict[langKey] as? String) ?? (nameDict["ar"] as? String) ?? (nameDict["en"] as? String) ?? ""
                } else if let nameStr = option["optionName"] as? String, !nameStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    optLabel = nameStr.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if optLabel.isEmpty {
                    switch optKey {
                    case "color", "colors", "colour", "اللون":
                        optLabel = isAr ? "اللون" : "Color"
                    case "size", "sizes", "المقاس", "الحجم":
                        optLabel = isAr ? "المقاس" : "Size"
                    case "weight", "weights", "الوزن":
                        optLabel = isAr ? "الوزن" : "Weight"
                    case "flavor", "flavors", "flavour", "flavours", "النكهة", "الطعم":
                        optLabel = isAr ? "النكهة" : "Flavor"
                    case "material", "materials", "المادة", "الخامة":
                        optLabel = isAr ? "المادة" : "Material"
                    case "volume", "capacity", "السعة":
                        optLabel = isAr ? "السعة" : "Volume"
                    default:
                        if !optKey.isEmpty {
                            optLabel = optKey.capitalized
                        }
                    }
                }

                // Resolve value label
                var valLabel = ""
                if let nameDict = option["valueName"] as? [String: Any] {
                    let langKey = isAr ? "ar" : "en"
                    valLabel = (nameDict[langKey] as? String) ?? (nameDict["ar"] as? String) ?? (nameDict["en"] as? String) ?? ""
                } else if let nameStr = option["valueName"] as? String, !nameStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    valLabel = nameStr.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if valLabel.isEmpty {
                    valLabel = (option["valueId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }

                if optKey.contains("size") || optLabel.contains("المقاس") || optLabel.lowercased().contains("size") {
                    valLabel = PetAccessory.formatStandardSize(valLabel)
                }

                if !valLabel.isEmpty {
                    if !optLabel.isEmpty {
                        parts.append("\(optLabel): \(valLabel)")
                    } else {
                        parts.append(valLabel)
                    }
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: " • ")
            }
        }

        // 2. Direct Color
        if pos_hasRealColor {
            let colName = pos_variantColorName
            if !colName.isEmpty {
                let colorPrefix = isAr ? "اللون" : "Color"
                parts.append("\(colorPrefix): \(colName)")
            }
        }

        // 3. Direct Size
        if let s = size?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            let sizePrefix = isAr ? "المقاس" : "Size"
            parts.append("\(sizePrefix): \(PetAccessory.formatStandardSize(s))")
        }

        // 4. Direct Weight
        if let w = weightText?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            let weightPrefix = isAr ? "الوزن" : "Weight"
            parts.append("\(weightPrefix): \(w)")
        } else if let numWeight = weight, numWeight.doubleValue > 0 {
            let weightPrefix = isAr ? "الوزن" : "Weight"
            let unit = weightUnit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? weightUnit!
                : (isAr ? "كجم" : "kg")
            parts.append("\(weightPrefix): \(numWeight) \(unit)")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " • ")
        }

        // 5. From selectedOptions dictionary
        if let options = selectedOptions, !options.isEmpty {
            for (k, v) in options {
                let strVal = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
                guard !strVal.isEmpty else { continue }
                let lk = k.lowercased()
                let prefix: String
                let formattedVal: String
                if lk.contains("color") || lk.contains("لون") {
                    prefix = isAr ? "اللون" : "Color"
                    formattedVal = strVal
                } else if lk.contains("size") || lk.contains("مقاس") || lk.contains("حجم") {
                    prefix = isAr ? "المقاس" : "Size"
                    formattedVal = PetAccessory.formatStandardSize(strVal)
                } else if lk.contains("weight") || lk.contains("وزن") {
                    prefix = isAr ? "الوزن" : "Weight"
                    formattedVal = strVal
                } else {
                    prefix = k
                    formattedVal = strVal
                }
                parts.append("\(prefix): \(formattedVal)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " • ")
            }
        }

        // 6. From variantCombinationKey (e.g. "color=blue|size=m")
        if let combo = variantCombinationKey, !combo.isEmpty {
            for part in combo.components(separatedBy: "|") {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 {
                    let k = kv[0].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !v.isEmpty else { continue }
                    let prefix: String
                    let formattedVal: String
                    if k.contains("color") {
                        prefix = isAr ? "اللون" : "Color"
                        formattedVal = v
                    } else if k.contains("size") {
                        prefix = isAr ? "المقاس" : "Size"
                        formattedVal = PetAccessory.formatStandardSize(v)
                    } else if k.contains("weight") {
                        prefix = isAr ? "الوزن" : "Weight"
                        formattedVal = v
                    } else {
                        prefix = kv[0]
                        formattedVal = v
                    }
                    parts.append("\(prefix): \(formattedVal)")
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: " • ")
            }
        }

        // 7. If isVariant or belongsToVariantFamily, fallback to pos_variantDisplayName if meaningful
        if isVariant || belongsToVariantFamily {
            let candidate = pos_variantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty && candidate != sku && candidate != accessoryID && candidate != name {
                if candidate.contains(":") {
                    return candidate
                }
                let axis = variantAxis?.lowercased() ?? ""
                if axis.contains("color") {
                    return "\(isAr ? "اللون" : "Color"): \(candidate)"
                } else if axis.contains("size") {
                    return "\(isAr ? "المقاس" : "Size"): \(PetAccessory.formatStandardSize(candidate))"
                } else if axis.contains("weight") {
                    return "\(isAr ? "الوزن" : "Weight"): \(candidate)"
                } else {
                    return "\(isAr ? "الخيار" : "Option"): \(candidate)"
                }
            }
        }

        return nil
    }

    /// Primary human-readable variant value for this product (e.g. "XS • صغير جداً", "أسود", "1 كجم").
    var pos_variantDisplayName: String {
        let isAr = Language.isRTL()

        // 1. From selectedOptionsSnapshot
        if let snapshot = selectedOptionsSnapshot, !snapshot.isEmpty {
            var labels: [String] = []
            for option in snapshot {
                if let nameDict = option["valueName"] as? [String: Any] {
                    let langKey = isAr ? "ar" : "en"
                    let val = (nameDict[langKey] as? String) ?? (nameDict["ar"] as? String) ?? (nameDict["en"] as? String) ?? ""
                    let valId = (option["valueId"] as? String) ?? ""
                    let candidate = val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? valId : val
                    let formatted = PetAccessory.formatStandardSize(candidate)
                    if !formatted.isEmpty {
                        labels.append(formatted)
                        continue
                    }
                } else if let nameStr = option["valueName"] as? String, !nameStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labels.append(PetAccessory.formatStandardSize(nameStr))
                    continue
                }

                if let valId = option["valueId"] as? String, !valId.isEmpty {
                    labels.append(PetAccessory.formatStandardSize(valId))
                }
            }
            if !labels.isEmpty {
                return labels.joined(separator: " / ")
            }
        }

        // 2. From selectedOptions dictionary
        if let options = selectedOptions, !options.isEmpty {
            var labels: [String] = []
            for (k, v) in options {
                let strVal = "\(v)"
                if k.lowercased().contains("size") {
                    labels.append(PetAccessory.formatStandardSize(strVal))
                } else {
                    labels.append(strVal)
                }
            }
            if !labels.isEmpty {
                return labels.joined(separator: " / ")
            }
        }

        // 3. From combinationKey
        if let combo = variantCombinationKey, !combo.isEmpty {
            let parts = combo.components(separatedBy: "|")
            var labels: [String] = []
            for part in parts {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 {
                    if kv[0].lowercased().contains("size") {
                        labels.append(PetAccessory.formatStandardSize(kv[1]))
                    } else {
                        labels.append(kv[1])
                    }
                }
            }
            if !labels.isEmpty {
                return labels.joined(separator: " / ")
            }
        }

        // 4. If genuine color, return color's localized name
        if pos_hasRealColor {
            let colName = pos_variantColorName
            if !colName.isEmpty { return colName }
        }

        // 5. From variantColorDictionary (e.g. legacy family where size was stored in nameAr)
        if let dict = variantColorDictionary {
            let raw = isAr ? (dict["nameAr"] as? String) : (dict["nameEn"] as? String)
            let fallback = (dict["nameAr"] ?? dict["nameEn"]) as? String
            let candidate = (raw ?? fallback)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !candidate.isEmpty && candidate != self.name && candidate != self.nameEn {
                return PetAccessory.formatStandardSize(candidate)
            }
        }

        // 6. From size property
        if let s = size?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return PetAccessory.formatStandardSize(s)
        }

        // 7. From weightText property
        if let w = weightText?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            return w
        }

        // 8. From SKU suffix heuristic (e.g. PP7899254789-XS -> صغير جداً (XS))
        if let sku = sku {
            let patterns = [
                ("-4XL", "4XL"), ("-3XL", "3XL"), ("-2XL", "2XL"), ("-XXL", "2XL"),
                ("-XL", "XL"), ("-XS", "XS"), ("-S", "S"), ("-M", "M"), ("-L", "L"),
                ("_4XL", "4XL"), ("_3XL", "3XL"), ("_2XL", "2XL"), ("_XXL", "2XL"),
                ("_XL", "XL"), ("_XS", "XS"), ("_S", "S"), ("_M", "M"), ("_L", "L")
            ]
            for (suffix, code) in patterns {
                if sku.uppercased().hasSuffix(suffix) {
                    return PetAccessory.formatStandardSize(code)
                }
            }
            if let lastDash = sku.lastIndex(of: "-") {
                let suffix = String(sku[sku.index(after: lastDash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !suffix.isEmpty && suffix.count <= 6 {
                    return PetAccessory.formatStandardSize(suffix)
                }
            }
        }

        // 9. If default variant, label as "الافتراضي"
        if isDefaultVariant {
            return Language.get("POS_DefaultVariant", alter: "الافتراضي")
        }

        // 10. Fallback to SKU or ID
        if let s = sku?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return accessoryID
    }

    /// Detects the collective variant dimension across all members in a family.
    static func detectFamilyDimension(members: [PetAccessory]) -> PPAccessoryVariantDimensionType {
        guard !members.isEmpty else { return .color }

        // 1. Check if any member has an explicit variantAxis
        for m in members {
            if let axis = m.variantAxis?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !axis.isEmpty {
                switch axis {
                case "size", "sizes", "المقاس", "الحجم": return .size
                case "weight", "weights", "الوزن": return .weight
                case "flavor", "flavors", "flavour", "flavours", "النكهة", "الطعم": return .flavor
                case "material", "materials", "المادة", "الخامة": return .material
                case "color", "colors", "اللون": return .color
                case "options", "multiple": return .multiple
                default: break
                }
            }
        }

        // 2. Collect dimensions of all members
        let dimensions = members.map { $0.pos_variantDimension }
        let uniqueDimensions = Set(dimensions)

        if uniqueDimensions.count > 1 && !uniqueDimensions.contains(.color) {
            return .multiple
        }

        if uniqueDimensions.contains(.size) {
            return .size
        }
        if uniqueDimensions.contains(.weight) {
            return .weight
        }
        if uniqueDimensions.contains(.flavor) {
            return .flavor
        }
        if uniqueDimensions.contains(.material) {
            return .material
        }

        // Check if any member has genuine color
        if members.contains(where: { $0.pos_hasRealColor }) {
            return .color
        }

        // If no real color and any dimension is custom, return custom
        if uniqueDimensions.contains(.custom) {
            return .custom
        }

        return .color
    }
}
