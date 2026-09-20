//
//  PuryAnswerStudio.swift
//  PurePetsAdmin
//
//  One answer, one viewer.
//
//  The defect this file exists to remove
//  -------------------------------------
//  The Pury backend can describe the same records three ways in a single reply: as markdown
//  prose in `text`, as `structuredData.cards`, and as `structuredData.dataBlocks`. The
//  previous surface rendered all three in sequence, so a ten-item stock query produced a
//  twelve-bullet prose list, then ten near-empty title-only cards, then ten full record
//  cards — the same facts, stacked three times, with "manage this product" repeated ten
//  times underneath.
//
//  `PuryAnswerProjection` collapses that: cards and data blocks are merged into one
//  entity-keyed record set, prose enumeration is dropped when the records themselves are
//  present (records are the canonical form of an enumeration), and the answer is then
//  classified into exactly one form. Nothing renders twice.
//
//  Why several viewers instead of one card style
//  --------------------------------------------
//  A repeated card stack is the wrong shape for ten records that share a field set: the
//  operator has to re-read the same labels ten times to compare two numbers. So each answer
//  shape gets the presentation its data actually wants:
//
//    • one record          -> Dossier      (spec sheet: identity, stat strip, definitions)
//    • stock collection    -> Stock Ledger (risk-ordered, level bars, triage filters)
//    • other collection    -> Roster       (one container, aligned columns, hairline rows)
//    • counts and metrics  -> Metric Board (value-first tiles)
//    • denial/stale/error  -> Exception    (cause, required permission, recovery)
//    • no matches          -> Verdict      (what was searched, how to widen it)
//
//  Every string resolves through `PuryLocale` in Pury's own language; numerals and backend
//  identifiers are forced left-to-right so they stay readable inside Arabic layout.
//

import SwiftUI
import UIKit

// MARK: - Field Semantics

/// What a backend field actually *is*, which decides how it is presented.
enum PuryFieldKind {
    case quantity
    case currency
    case boolean
    case identifier
    case date
    case text
}

enum PuryFieldSemantics {
    /// Normalized comparison key for a backend label.
    static func key(_ label: String) -> String {
        label
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func kind(label: String, value: String) -> PuryFieldKind {
        let k = key(label)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if ["true", "false", "yes", "no"].contains(v) { return .boolean }
        if k.contains("quantity") || k.contains("qty") || k.contains("stock") || k.contains("الكمية") || k.contains("كمية") {
            return .quantity
        }
        if k.contains("price") || k.contains("cost") || k.contains("total") || k.contains("سعر") || k.contains("تكلفة") {
            return .currency
        }
        if k.hasSuffix("id") || k == "collection" || k == "docid" || k == "sku" || k == "barcode" {
            return .identifier
        }
        if k.contains("date") || k.contains("checkin") || k.contains("checkout") || k.contains("created")
            || k.contains("updated") || k.contains("تاريخ") {
            return .date
        }
        return .text
    }

    /// Operator-facing label. Extends the humanizer to the raw keys that were leaking into
    /// the Arabic surface untranslated: `Final price`, `Visible in app`, `collection`,
    /// `English name`.
    static func label(_ raw: String, language: String) -> String {
        switch key(raw) {
        case "availablequantity", "quantity", "qty", "stock", "instock":
            return PuryLocale.text("Pury_Field_AvailableQuantity", language: language, ar: "الكمية المتوفرة", en: "Available quantity")
        case "price", "unitprice":
            return PuryLocale.text("Pury_Field_Price", language: language, ar: "السعر", en: "Price")
        case "finalprice", "priceafterdiscount", "netprice":
            return PuryLocale.text("Pury_Field_FinalPrice", language: language, ar: "السعر النهائي", en: "Final price")
        case "visibleinapp", "showinapp", "showinappmarket":
            return PuryLocale.text("Pury_Field_VisibleInApp", language: language, ar: "الظهور في التطبيق", en: "Visible in app")
        case "collection":
            return PuryLocale.text("Pury_Field_Collection", language: language, ar: "المجموعة", en: "Collection")
        case "englishname", "nameen", "titleen":
            return PuryLocale.text("Pury_Field_EnglishName", language: language, ar: "الاسم بالإنجليزية", en: "English name")
        case "arabicname", "namear", "titlear":
            return PuryLocale.text("Pury_Field_ArabicName", language: language, ar: "الاسم بالعربية", en: "Arabic name")
        case "category", "categoryname":
            return PuryLocale.text("Pury_Field_Category", language: language, ar: "التصنيف", en: "Category")
        case "status", "state":
            return PuryLocale.text("Pury_Field_Status", language: language, ar: "الحالة", en: "Status")
        case "description", "desc":
            return PuryLocale.text("Pury_Field_Description", language: language, ar: "الوصف", en: "Description")
        case "name", "title":
            return PuryLocale.text("Pury_Field_Name", language: language, ar: "الاسم", en: "Name")
        default:
            return raw
        }
    }

    /// Operator-facing value. Booleans become words, collection identities become names,
    /// and raw identifiers stay verbatim (they are looked up, not read).
    static func value(_ raw: String, label: String, language: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "true", "yes":
            // Plain forms without shadda: the brand face renders the diacritic unreliably.
            return PuryLocale.text("Pury_Value_On", language: language, ar: "مفعل", en: "On")
        case "false", "no":
            return PuryLocale.text("Pury_Value_Off", language: language, ar: "معطل", en: "Off")
        default:
            break
        }

        if key(label) == "collection", let name = collectionName(trimmed, language: language) {
            return name
        }
        return trimmed
    }

    static func collectionName(_ identifier: String, language: String) -> String? {
        switch key(identifier) {
        case "petaccessories":
            return PuryLocale.text("Pury_Collection_PetAccessories", language: language, ar: "مستلزمات وأغذية", en: "Accessories & food")
        case "userscol", "users":
            return PuryLocale.text("Pury_Record_Customer", language: language, ar: "ملف العميل", en: "Customer Profile")
        case "staffusers":
            return PuryLocale.text("Pury_Record_StaffMember", language: language, ar: "عضو الفريق", en: "Staff Member")
        case "branches":
            return PuryLocale.text("Pury_Record_Branch", language: language, ar: "بيانات الفرع", en: "Branch Record")
        case "orders", "paymentorder":
            return PuryLocale.text("Pury_Record_Order", language: language, ar: "طلب", en: "Order")
        case "hotelstays":
            return PuryLocale.text("Pury_Record_HotelStay", language: language, ar: "إقامة فندقية", en: "Hotel Stay")
        default:
            return nil
        }
    }

    /// Whole numbers only; the backend sends quantities as strings.
    static func integer(_ raw: String) -> Int? {
        let digits = raw.filter { $0.isNumber || $0 == "-" }
        guard !digits.isEmpty, digits.count == raw.trimmingCharacters(in: .whitespaces).count || raw.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "-" }) else {
            return Int(digits)
        }
        return Int(digits)
    }
}

// MARK: - Record Projection

/// One operational entity, regardless of whether the backend expressed it as a card, a data
/// block, or both. Merging on identity is what stops the same record rendering twice.
struct PuryRecordProjection: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let status: String?
    let badge: String?
    let entityType: String?
    let entityId: String?
    let collection: String?
    let fields: [PuryField]
    let actionRoute: String?

    static func == (lhs: PuryRecordProjection, rhs: PuryRecordProjection) -> Bool {
        lhs.id == rhs.id
    }

    func field(matching keys: [String]) -> PuryField? {
        fields.first { field in
            let k = PuryFieldSemantics.key(field.cleanLabel)
            return keys.contains { k.contains($0) }
        }
    }

    var quantity: Int? {
        guard let field = field(matching: ["quantity", "qty", "stock", "الكمية", "كمية"]) else { return nil }
        return PuryFieldSemantics.integer(field.cleanValue)
    }

    var priceText: String? {
        field(matching: ["finalprice", "price", "سعر"])?.cleanValue
    }

    /// `nil` when the record says nothing about app visibility.
    var isVisibleInApp: Bool? {
        guard let field = field(matching: ["visibleinapp", "showinapp", "showinappmarket", "الظهور"]) else { return nil }
        switch field.cleanValue.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "مفعل", "مفعّل": return true
        case "false", "no", "معطل", "معطّل": return false
        default: return nil
        }
    }

    var navigationType: String? {
        if let actionRoute, !actionRoute.isEmpty { return actionRoute }
        if let entityType, !entityType.isEmpty { return entityType }
        return collection
    }

    /// A disclosure is truthful only when it can reveal server-provided fields or open the
    /// exact record represented by this row. A title alone is not an interaction.
    var canOpenRecord: Bool {
        guard let entityId = entityId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entityId.isEmpty,
              let navigationType = navigationType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !navigationType.isEmpty else {
            return false
        }
        return true
    }

    var hasDisclosure: Bool {
        !fields.isEmpty || canOpenRecord
    }
}

// MARK: - Stock Risk

enum PuryStockRisk: Int, CaseIterable {
    case depleted = 0
    case critical = 1
    case low = 2
    case healthy = 3

    static func classify(quantity: Int?) -> PuryStockRisk {
        guard let quantity else { return .healthy }
        if quantity <= 0 { return .depleted }
        if quantity <= 3 { return .critical }
        if quantity <= 10 { return .low }
        return .healthy
    }

    var tint: Color {
        switch self {
        case .depleted: return AdminSurface.crimson
        case .critical: return AdminSurface.amber
        case .low: return Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255)
        case .healthy: return AdminSurface.emerald
        }
    }

    func label(language: String) -> String {
        switch self {
        case .depleted:
            return PuryLocale.text("Pury_Stock_Risk_Depleted", language: language, ar: "نفد", en: "Out")
        case .critical:
            return PuryLocale.text("Pury_Stock_Risk_Critical", language: language, ar: "حرج", en: "Critical")
        case .low:
            return PuryLocale.text("Pury_Stock_Risk_Low", language: language, ar: "منخفض", en: "Low")
        case .healthy:
            return PuryLocale.text("Pury_Stock_Risk_Healthy", language: language, ar: "متوفر", en: "Healthy")
        }
    }
}

// MARK: - Answer Form

enum PuryExceptionKind {
    case denied
    case stale
    case failed
}

/// Exactly one of these is rendered per answer.
enum PuryAnswerForm {
    case exception(PuryExceptionKind)
    case emptyVerdict
    case advisory
    case dossier(PuryRecordProjection)
    case stockLedger([PuryRecordProjection])
    case roster([PuryRecordProjection])
    case metricBoard([PuryRecordProjection])
}

enum PuryNarrativeDisposition {
    /// No records were returned: the prose *is* the answer.
    case full
    /// Records were returned: keep only interpretation, never the enumeration.
    case advisoryOnly
}

// MARK: - Projection Resolver

enum PuryAnswerProjection {
    /// Backend field keys that are plumbing, not information.
    private static let technicalFieldKeys: Set<String> = [
        "id", "docid", "ownerid", "userid", "petid", "reservationid", "stayid",
        "accommodationid", "roomid", "suiteid", "isdeleted", "deleted", "isblocked",
        "blocked", "accesskindtype", "kindtype", "raw", "payload", "__name__",
        "fcmtoken", "createdatmillis", "updatedatmillis", "hash", "version"
    ]

    /// Merges `cards` and `dataBlocks` into one record set keyed by entity identity.
    static func records(for metadata: PuryResponseMetadata?) -> [PuryRecordProjection] {
        guard let structured = metadata?.structuredData else { return [] }

        var order: [String] = []
        var merged: [String: PuryRecordProjection] = [:]
        var identifierIndex: [String: String] = [:]
        // An identity-less legacy card can join a matching record by title. That fallback
        // never makes two already identified records with the same title collapse.
        var titleFallbackIndex: [String: String] = [:]

        func normalizedIdentifier(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        func normalizedTitleKey(_ title: String) -> String? {
            let folded = title
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return folded.isEmpty ? nil : "title:\(folded)"
        }

        func identityKey(entityId: String?, title: String) -> String {
            if let entityId = normalizedIdentifier(entityId) { return "id:\(entityId)" }
            return normalizedTitleKey(title) ?? "anonymous:\(order.count)"
        }

        func hasIdentifier(_ record: PuryRecordProjection?) -> Bool {
            normalizedIdentifier(record?.entityId) != nil
        }

        func cleanedFields(_ fields: [PuryField]) -> [PuryField] {
            fields.filter { !technicalFieldKeys.contains(PuryFieldSemantics.key($0.cleanLabel)) }
        }

        func absorb(
            title: String,
            subtitle: String?,
            status: String?,
            badge: String?,
            entityType: String?,
            entityId: String?,
            collection: String?,
            fields: [PuryField],
            actionRoute: String?
        ) {
            let normalizedEntityId = normalizedIdentifier(entityId)
            let titleKey = normalizedTitleKey(title)
            let key: String

            if let normalizedEntityId, let indexedKey = identifierIndex[normalizedEntityId] {
                key = indexedKey
            } else if normalizedEntityId == nil,
                      let titleKey,
                      let indexedKey = titleFallbackIndex[titleKey] {
                key = indexedKey
            } else if let titleKey,
                      let indexedKey = titleFallbackIndex[titleKey],
                      !hasIdentifier(merged[indexedKey]) {
                // The incoming field-bearing record supplies the missing identifier for
                // an older title-only card, so this is the same entity.
                key = indexedKey
            } else {
                key = identityKey(entityId: normalizedEntityId, title: title)
                order.append(key)
            }

            if let existing = merged[key] {
                var combined = existing.fields
                let known = Set(existing.fields.map { PuryFieldSemantics.key($0.cleanLabel) })
                for field in fields where !known.contains(PuryFieldSemantics.key(field.cleanLabel)) {
                    combined.append(field)
                }
                merged[key] = PuryRecordProjection(
                    id: existing.id,
                    title: existing.title.isEmpty ? title : existing.title,
                    subtitle: existing.subtitle ?? subtitle,
                    status: existing.status ?? status,
                    badge: existing.badge ?? badge,
                    entityType: existing.entityType ?? entityType,
                    entityId: normalizedIdentifier(existing.entityId) ?? normalizedEntityId,
                    collection: existing.collection ?? collection,
                    fields: combined,
                    actionRoute: existing.actionRoute ?? actionRoute
                )
            } else {
                merged[key] = PuryRecordProjection(
                    id: key,
                    title: title,
                    subtitle: subtitle,
                    status: status,
                    badge: badge,
                    entityType: entityType,
                    entityId: normalizedEntityId,
                    collection: collection,
                    fields: fields,
                    actionRoute: actionRoute
                )
            }

            if let normalizedEntityId {
                identifierIndex[normalizedEntityId] = key
            }
            if let titleKey, titleFallbackIndex[titleKey] == nil {
                titleFallbackIndex[titleKey] = key
            }
        }

        // Cards contribute identity and framing.
        for card in structured.cards ?? [] {
            let title = card.cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = cleanedFields(card.details ?? [])
            // A card with only a title carries nothing a record row does not already show,
            // and previously rendered as an empty box. It still counts as identity, so it
            // is absorbed rather than dropped — it just never becomes its own surface.
            guard !title.isEmpty || !fields.isEmpty else { continue }
            absorb(
                title: title,
                subtitle: card.cleanSubtitle,
                status: card.status,
                badge: card.badge,
                entityType: card.entityType,
                entityId: card.entityId,
                collection: nil,
                fields: fields,
                actionRoute: card.actionRoute
            )
        }

        // Data blocks contribute the field payload.
        for block in structured.dataBlocks ?? [] {
            let fields = cleanedFields(block.fields)
            guard !fields.isEmpty else { continue }
            let nameField = fields.first { field in
                ["name", "title", "productname", "petname", "arabicname"].contains(PuryFieldSemantics.key(field.cleanLabel))
            }
            let title = (nameField?.cleanValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = nameField == nil ? fields : fields.filter { $0.cleanLabel != nameField?.cleanLabel }
            absorb(
                title: title,
                subtitle: nil,
                status: nil,
                badge: nil,
                entityType: block.type,
                entityId: block.id,
                collection: block.collection,
                fields: remaining,
                actionRoute: nil
            )
        }

        // Records with neither a title nor fields cannot be presented truthfully.
        return order.compactMap { merged[$0] }.filter { !$0.title.isEmpty || !$0.fields.isEmpty }
    }

    static func disposition(recordCount: Int) -> PuryNarrativeDisposition {
        recordCount > 0 ? .advisoryOnly : .full
    }

    /// Chooses the single viewer for this answer.
    static func form(
        metadata: PuryResponseMetadata?,
        records: [PuryRecordProjection],
        hasNarrative: Bool
    ) -> PuryAnswerForm {
        if let error = metadata?.error, !error.isEmpty {
            switch error {
            case "permission_denied": return .exception(.denied)
            case "conflict_stale": return .exception(.stale)
            default: return .exception(.failed)
            }
        }

        if records.isEmpty {
            if metadata?.result_count == 0 && !hasNarrative { return .emptyVerdict }
            return hasNarrative ? .advisory : .emptyVerdict
        }

        if records.count == 1, let single = records.first {
            return .dossier(single)
        }

        if isStockCollection(records) {
            return .stockLedger(records)
        }

        if isMetricSet(metadata: metadata, records: records) {
            return .metricBoard(records)
        }

        return .roster(records)
    }

    /// Stock shape: the records talk about quantity, and about price or app visibility.
    private static func isStockCollection(_ records: [PuryRecordProjection]) -> Bool {
        let withQuantity = records.filter { $0.quantity != nil }
        guard Double(withQuantity.count) / Double(records.count) >= 0.6 else { return false }
        return records.contains { $0.priceText != nil || $0.isVisibleInApp != nil }
    }

    /// Metric shape: a declared counting operation over records that are one value each.
    private static func isMetricSet(metadata: PuryResponseMetadata?, records: [PuryRecordProjection]) -> Bool {
        let signature = [metadata?.intent, metadata?.domain, metadata?.operation]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let declaresCounting = ["count", "metric", "kpi", "summary", "stats", "aggregate"]
            .contains { signature.contains($0) }
        guard declaresCounting else { return false }
        return records.allSatisfy { $0.fields.count <= 2 }
    }
}

// MARK: - Shared Atoms

/// Numerals, prices, and identifiers are read left-to-right in both languages.
private struct PuryNumeral: View {
    let text: String
    var size: CGFloat = 17
    var weight: Font.Weight = .bold
    var tint: Color = AdminSurface.primaryText

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The container every answer viewer sits in: one surface, so a ten-record answer reads as
/// one object instead of ten floating cards.
private struct PuryAnswerSurface<Content: View>: View {
    var accent: Color = PuryBrand.primary
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.16), lineWidth: 0.9)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 9, x: 0, y: 4)
    }
}

private struct PuryAnswerSectionHeader: View {
    let symbol: String
    let title: String
    let detail: String?
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let detail {
                Text(detail)
                    .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct PuryFieldRow: View {
    let field: PuryField
    let language: String

    var body: some View {
        let kind = PuryFieldSemantics.kind(label: field.cleanLabel, value: field.cleanValue)
        let label = PuryFieldSemantics.label(field.cleanLabel, language: language)
        let value = PuryFieldSemantics.value(field.cleanValue, label: field.cleanLabel, language: language)

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(PPBrandFont.regular(size: 12, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            switch kind {
            case .quantity, .currency:
                PuryNumeral(text: value, size: 13, weight: .semibold)
            case .identifier:
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
            case .boolean:
                Text(value)
                    .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))
                    .foregroundStyle(value == PuryLocale.text("Pury_Value_Off", language: language, ar: "معطل", en: "Off") ? AdminSurface.crimson : AdminSurface.emerald)
            default:
                Text(value)
                    .font(PPBrandFont.medium(size: 12.5, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct PuryAnswerAction: View {
    let title: String
    let symbol: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))

                Text(title)
                    .font(PPBrandFont.bold(size: 12.5, relativeTo: .caption))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.07))
        }
        .buttonStyle(PuryTactilePressStyle(pressedScale: 0.99))
        .accessibilityLabel(title)
    }
}

private struct PuryHairline: View {
    var body: some View {
        Rectangle()
            .fill(AdminSurface.hairline)
            .frame(height: 0.5)
    }
}

// MARK: - Stock Ledger

/// Risk-ordered inventory triage. The leading level bars turn the list into a single
/// readable gradient of exposure, and the whole set shares one "manage inventory" action
/// instead of repeating a deep link on every row.
@available(iOS 16.0, *)
struct PuryStockLedgerView: View {
    let records: [PuryRecordProjection]
    let language: String
    let isRTL: Bool
    let onOpenInventory: () -> Void
    let onOpenRecord: (PuryRecordProjection) -> Void

    @State private var riskFilter: PuryStockRisk? = nil
    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ordered: [PuryRecordProjection] {
        records.sorted { lhs, rhs in
            let l = lhs.quantity ?? Int.max
            let r = rhs.quantity ?? Int.max
            if l != r { return l < r }
            return lhs.title < rhs.title
        }
    }

    private var visible: [PuryRecordProjection] {
        guard let riskFilter else { return ordered }
        return ordered.filter { PuryStockRisk.classify(quantity: $0.quantity) == riskFilter }
    }

    private var tallies: [(risk: PuryStockRisk, count: Int)] {
        PuryStockRisk.allCases.compactMap { risk in
            let count = ordered.filter { PuryStockRisk.classify(quantity: $0.quantity) == risk }.count
            return count > 0 ? (risk, count) : nil
        }
    }

    /// Scale for the level bars: the healthiest item in the answer sets full height, so the
    /// bars encode relative exposure within what the operator actually asked about.
    private var scale: Int {
        max(1, ordered.compactMap { $0.quantity }.max() ?? 1)
    }

    var body: some View {
        PuryAnswerSurface(accent: AdminSurface.amber) {
            VStack(alignment: .leading, spacing: 0) {
                PuryAnswerSectionHeader(
                    symbol: "shippingbox.fill",
                    title: PuryLocale.text("Pury_Answer_Stock_Title", language: language, ar: "حالة المخزون", en: "Stock exposure"),
                    detail: "\(ordered.count)",
                    accent: AdminSurface.amber
                )

                if tallies.count > 1 {
                    triageRail
                    PuryHairline()
                }

                ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { PuryHairline() }
                    row(record)
                }

                if visible.isEmpty {
                    Text(
                        PuryLocale.text(
                            "Pury_Answer_Filter_Empty",
                            language: language,
                            ar: "لا عناصر في هذا التصنيف",
                            en: "No items in this band"
                        )
                    )
                    .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(14)
                }

                PuryHairline()

                PuryAnswerAction(
                    title: PuryLocale.text("Pury_Answer_Manage_Inventory", language: language, ar: "إدارة المخزون", en: "Manage inventory"),
                    symbol: "square.stack.3d.up.fill",
                    accent: AdminSurface.amber,
                    action: onOpenInventory
                )
            }
        }
    }

    /// Local triage filter. Real, immediate, and derived entirely from the answer's own data.
    private var triageRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tallies, id: \.risk.rawValue) { tally in
                    let isActive = riskFilter == tally.risk
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                            riskFilter = isActive ? nil : tally.risk
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tally.risk.tint)
                                .frame(width: 6, height: 6)

                            Text(tally.risk.label(language: language))
                                .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))

                            PuryNumeral(text: "\(tally.count)", size: 11, weight: .heavy, tint: isActive ? .white : tally.risk.tint)
                        }
                        .foregroundStyle(isActive ? Color.white : AdminSurface.primaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(isActive ? tally.risk.tint : tally.risk.tint.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(PuryTactilePressStyle(pressedScale: 0.94))
                    .accessibilityLabel("\(tally.risk.label(language: language)) \(tally.count)")
                    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 11)
        }
    }

    private func row(_ record: PuryRecordProjection) -> some View {
        let quantity = record.quantity
        let risk = PuryStockRisk.classify(quantity: quantity)
        let canRevealDetails = record.hasDisclosure
        let isOpen = canRevealDetails && expanded.contains(record.id)
        let hidden = record.isVisibleInApp == false

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if canRevealDetails {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) {
                            if isOpen { expanded.remove(record.id) } else { expanded.insert(record.id) }
                        }
                    } label: {
                        stockRowLabel(
                            record: record,
                            quantity: quantity,
                            risk: risk,
                            hidden: hidden,
                            isOpen: isOpen,
                            showsDisclosure: true
                        )
                    }
                    .buttonStyle(PuryTactilePressStyle(pressedScale: 0.995))
                    .accessibilityLabel(rowAccessibilityLabel(record: record, risk: risk, quantity: quantity))
                    .accessibilityHint(
                        PuryLocale.text("Pury_Answer_Row_Hint", language: language, ar: "انقر مرتين لعرض التفاصيل", en: "Double tap for details")
                    )
                } else {
                    stockRowLabel(
                        record: record,
                        quantity: quantity,
                        risk: risk,
                        hidden: hidden,
                        isOpen: false,
                        showsDisclosure: false
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rowAccessibilityLabel(record: record, risk: risk, quantity: quantity))
                }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(record.fields) { field in
                        PuryFieldRow(field: field, language: language)
                    }

                    if record.canOpenRecord {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onOpenRecord(record)
                        } label: {
                            HStack(spacing: 5) {
                                Text(PuryLocale.text("Pury_Answer_Open_Record", language: language, ar: "فتح السجل", en: "Open record"))
                                    .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption2))
                                Image(systemName: "arrow.forward")
                                    .font(.system(size: 9, weight: .black))
                            }
                            .foregroundStyle(PuryBrand.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private func stockRowLabel(
        record: PuryRecordProjection,
        quantity: Int?,
        risk: PuryStockRisk,
        hidden: Bool,
        isOpen: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 11) {
            levelBar(quantity: quantity, risk: risk)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.title)
                        .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    if hidden {
                        Text(PuryLocale.text("Pury_Stock_Hidden", language: language, ar: "مخفي", en: "Hidden"))
                            .font(PPBrandFont.bold(size: 9.5, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.crimson)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text(risk.label(language: language))
                        .font(PPBrandFont.bold(size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(risk.tint)

                    if let price = record.priceText {
                        Text("·")
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                        PuryNumeral(text: price, size: 10.5, weight: .medium, tint: AdminSurface.secondaryText)
                    }
                }
            }

            Spacer(minLength: 6)

            if let quantity {
                VStack(alignment: .trailing, spacing: 0) {
                    PuryNumeral(text: "\(quantity)", size: 19, weight: .heavy, tint: risk.tint)

                    Text(PuryLocale.text("Pury_Stock_Unit", language: language, ar: "وحدة", en: "units"))
                        .font(PPBrandFont.regular(size: 9, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.55))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// A 3pt column whose fill height encodes exposure. Reading the column down the list is
    /// faster than reading ten numbers.
    private func levelBar(quantity: Int?, risk: PuryStockRisk) -> some View {
        let fraction: CGFloat = {
            guard let quantity, quantity > 0 else { return 0 }
            return max(0.08, min(1, CGFloat(quantity) / CGFloat(scale)))
        }()

        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(AdminSurface.control)

            Capsule()
                .fill(risk.tint)
                .frame(height: max(3, 34 * fraction))

            if quantity == 0 {
                Capsule()
                    .fill(AdminSurface.crimson)
                    .frame(height: 3)
            }
        }
        .frame(width: 3.5, height: 34)
        .accessibilityHidden(true)
    }

    private func rowAccessibilityLabel(record: PuryRecordProjection, risk: PuryStockRisk, quantity: Int?) -> String {
        var parts = [record.title, risk.label(language: language)]
        if let quantity {
            parts.append(
                PuryLocale.format(
                    "Pury_Stock_Units_Format",
                    language: language,
                    ar: "%@ وحدات متوفرة",
                    en: "%@ units available",
                    String(quantity)
                )
            )
        }
        if record.isVisibleInApp == false {
            parts.append(PuryLocale.text("Pury_Stock_Hidden", language: language, ar: "مخفي", en: "Hidden"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Record Roster

/// Many records of one collection, in one container with aligned columns. The two most
/// common fields across the set become shared columns so values line up and can be compared
/// down the list instead of re-read per card.
@available(iOS 16.0, *)
struct PuryRecordRosterView: View {
    let records: [PuryRecordProjection]
    let language: String
    let isRTL: Bool
    let title: String
    let symbol: String
    let onOpenRecord: (PuryRecordProjection) -> Void

    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Labels present on most records, in first-seen order.
    private var sharedColumns: [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for record in records {
            for field in record.fields {
                let key = PuryFieldSemantics.key(field.cleanLabel)
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            }
        }
        let threshold = max(2, Int(Double(records.count) * 0.7))
        return order.filter { counts[$0, default: 0] >= threshold }.prefix(2).map { $0 }
    }

    var body: some View {
        PuryAnswerSurface(accent: PuryBrand.primary) {
            VStack(alignment: .leading, spacing: 0) {
                PuryAnswerSectionHeader(
                    symbol: symbol,
                    title: title,
                    detail: "\(records.count)",
                    accent: PuryBrand.primary
                )

                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { PuryHairline() }
                    row(record)
                }
            }
        }
    }

    private func row(_ record: PuryRecordProjection) -> some View {
        let canRevealDetails = record.hasDisclosure
        let isOpen = canRevealDetails && expanded.contains(record.id)
        let columns = sharedColumns
        let summary = columns.compactMap { key in
            record.fields.first { PuryFieldSemantics.key($0.cleanLabel) == key }
        }
        let rest = record.fields.filter { !columns.contains(PuryFieldSemantics.key($0.cleanLabel)) }

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if canRevealDetails {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) {
                            if isOpen { expanded.remove(record.id) } else { expanded.insert(record.id) }
                        }
                    } label: {
                        rosterRowLabel(record: record, summary: summary, isOpen: isOpen, showsDisclosure: true)
                    }
                    .buttonStyle(PuryTactilePressStyle(pressedScale: 0.995))
                    .accessibilityHint(
                        PuryLocale.text("Pury_Answer_Row_Hint", language: language, ar: "انقر مرتين لعرض التفاصيل", en: "Double tap for details")
                    )
                } else {
                    rosterRowLabel(record: record, summary: summary, isOpen: false, showsDisclosure: false)
                        .accessibilityElement(children: .combine)
                }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(rest) { field in
                        PuryFieldRow(field: field, language: language)
                    }

                    if record.canOpenRecord {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onOpenRecord(record)
                        } label: {
                            HStack(spacing: 5) {
                                Text(PuryLocale.text("Pury_Answer_Open_Record", language: language, ar: "فتح السجل", en: "Open record"))
                                    .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption2))
                                Image(systemName: "arrow.forward")
                                    .font(.system(size: 9, weight: .black))
                            }
                            .foregroundStyle(PuryBrand.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private func rosterRowLabel(
        record: PuryRecordProjection,
        summary: [PuryField],
        isOpen: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? PuryLocale.text("Pury_Record_Generic", language: language, ar: "بيانات السجل", en: "Record Details") : record.title)
                    .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                if let subtitle = record.subtitle ?? record.status {
                    Text(subtitle)
                        .font(PPBrandFont.regular(size: 11, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Aligned shared columns: comparable down the list.
            HStack(spacing: 12) {
                ForEach(summary) { field in
                    let kind = PuryFieldSemantics.kind(label: field.cleanLabel, value: field.cleanValue)
                    let value = PuryFieldSemantics.value(field.cleanValue, label: field.cleanLabel, language: language)
                    if kind == .quantity || kind == .currency {
                        PuryNumeral(text: value, size: 13, weight: .bold)
                    } else {
                        Text(value)
                            .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.55))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Record Dossier

/// One record deserves depth, not a list row: identity band, a stat strip of the numbers an
/// operator acts on, then the remaining fields as a definition list.
@available(iOS 16.0, *)
struct PuryRecordDossierView: View {
    let record: PuryRecordProjection
    let language: String
    let isRTL: Bool
    let recordTypeName: String
    let symbol: String
    let accent: Color
    let onOpenRecord: (PuryRecordProjection) -> Void

    private var statFields: [PuryField] {
        record.fields.filter { field in
            let kind = PuryFieldSemantics.kind(label: field.cleanLabel, value: field.cleanValue)
            return kind == .quantity || kind == .currency
        }
        .prefix(3)
        .map { $0 }
    }

    private var detailFields: [PuryField] {
        let statKeys = Set(statFields.map { PuryFieldSemantics.key($0.cleanLabel) })
        return record.fields.filter { !statKeys.contains(PuryFieldSemantics.key($0.cleanLabel)) }
    }

    var body: some View {
        PuryAnswerSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 0) {
                identityBand

                if !statFields.isEmpty {
                    PuryHairline()
                    statStrip
                }

                if !detailFields.isEmpty {
                    PuryHairline()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(detailFields) { field in
                            PuryFieldRow(field: field, language: language)
                        }
                    }
                    .padding(14)
                }

                if record.canOpenRecord {
                    PuryHairline()
                    PuryAnswerAction(
                        title: PuryLocale.text("Pury_Answer_Open_Record", language: language, ar: "فتح السجل", en: "Open record"),
                        symbol: "arrow.up.forward.app.fill",
                        accent: accent,
                        action: { onOpenRecord(record) }
                    )
                }
            }
        }
    }

    private var identityBand: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? recordTypeName : record.title)
                    .font(PPBrandFont.bold(size: 17, relativeTo: .headline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recordTypeName)
                    .font(PPBrandFont.regular(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer(minLength: 6)

            if let status = record.status ?? record.badge {
                Text(status)
                    .font(PPBrandFont.bold(size: 10.5, relativeTo: .caption2))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    /// Value-first tiles: the number leads, the label supports it.
    private var statStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(statFields.enumerated()), id: \.element.id) { index, field in
                if index > 0 {
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(width: 0.5, height: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    PuryNumeral(
                        text: PuryFieldSemantics.value(field.cleanValue, label: field.cleanLabel, language: language),
                        size: 18,
                        weight: .heavy,
                        tint: accent
                    )

                    Text(PuryFieldSemantics.label(field.cleanLabel, language: language))
                        .font(PPBrandFont.regular(size: 10, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Metric Board

@available(iOS 16.0, *)
struct PuryMetricBoardView: View {
    let records: [PuryRecordProjection]
    let language: String
    let title: String
    let onOpenRecord: (PuryRecordProjection) -> Void

    var body: some View {
        PuryAnswerSurface(accent: PuryBrand.violet) {
            VStack(alignment: .leading, spacing: 0) {
                PuryAnswerSectionHeader(
                    symbol: "chart.bar.fill",
                    title: title,
                    detail: "\(records.count)",
                    accent: PuryBrand.violet
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132), spacing: 10, alignment: .top)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(records) { record in
                        tile(record)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    private func tile(_ record: PuryRecordProjection) -> some View {
        let value = record.fields.first.map {
            PuryFieldSemantics.value($0.cleanValue, label: $0.cleanLabel, language: language)
        }

        return VStack(alignment: .leading, spacing: 4) {
            if let value {
                PuryNumeral(text: value, size: 22, weight: .heavy, tint: PuryBrand.violet)
            }

            Text(record.title)
                .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PuryBrand.violet.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PuryBrand.violet.opacity(0.16), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Exception Panel

/// A refusal is an answer. Denials, stale-data conflicts, and failures previously rendered
/// as ordinary grey prose; here each states its cause, the permission or condition
/// responsible, and the recovery the operator actually has.
@available(iOS 16.0, *)
struct PuryExceptionPanel: View {
    let kind: PuryExceptionKind
    let summary: String
    let requiredPermission: String?
    let language: String
    let onRetry: (() -> Void)?

    private var accent: Color {
        switch kind {
        case .denied: return AdminSurface.crimson
        case .stale: return AdminSurface.amber
        case .failed: return AdminSurface.crimson
        }
    }

    private var symbol: String {
        switch kind {
        case .denied: return "lock.shield.fill"
        case .stale: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch kind {
        case .denied:
            return PuryLocale.text("Pury_Exception_Denied_Title", language: language, ar: "صلاحيتك لا تسمح بهذا الطلب", en: "Your permissions don't allow this")
        case .stale:
            return PuryLocale.text("Pury_Exception_Stale_Title", language: language, ar: "تغيّرت البيانات قبل التنفيذ", en: "Records changed before execution")
        case .failed:
            return PuryLocale.text("Pury_Exception_Failed_Title", language: language, ar: "تعذّر إكمال الطلب", en: "The request could not be completed")
        }
    }

    private var guidance: String {
        switch kind {
        case .denied:
            return PuryLocale.text(
                "Pury_Exception_Denied_Guidance",
                language: language,
                ar: "التحقق يتم على الخادم. اطلب الصلاحية من مالك الحساب لمتابعة هذا الإجراء.",
                en: "Authorization is enforced server-side. Ask an account owner to grant this permission."
            )
        case .stale:
            return PuryLocale.text(
                "Pury_Exception_Stale_Guidance",
                language: language,
                ar: "أعد الاستعلام لقراءة أحدث نسخة قبل اتخاذ أي إجراء.",
                en: "Re-run the query to read the latest revision before acting."
            )
        case .failed:
            return PuryLocale.text(
                "Pury_Exception_Failed_Guidance",
                language: language,
                ar: "لم يتم تنفيذ أي تغيير. يمكنك إعادة المحاولة.",
                en: "No change was applied. You can try again."
            )
        }
    }

    var body: some View {
        PuryAnswerSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(headline)
                            .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if !summary.isEmpty {
                            Text(summary)
                                .font(PPBrandFont.regular(size: 13, relativeTo: .footnote))
                                .foregroundStyle(AdminSurface.primaryText.opacity(0.85))
                                .lineSpacing(4)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(guidance)
                            .font(PPBrandFont.regular(size: 12, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)

                if let requiredPermission, !requiredPermission.isEmpty {
                    PuryHairline()
                    HStack(spacing: 8) {
                        Text(
                            PuryLocale.text(
                                "Pury_Exception_Required_Permission",
                                language: language,
                                ar: "الصلاحية المطلوبة",
                                en: "Required permission"
                            )
                        )
                        .font(PPBrandFont.regular(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)

                        Spacer(minLength: 8)

                        Text(requiredPermission)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }

                if let onRetry {
                    PuryHairline()
                    PuryAnswerAction(
                        title: PuryLocale.text("Pury_Turn_Rerun", language: language, ar: "إعادة الاستعلام", en: "Re-run query"),
                        symbol: "arrow.clockwise",
                        accent: accent,
                        action: onRetry
                    )
                }
            }
        }
    }
}

// MARK: - Empty Verdict

/// "Nothing matched" is a finding, not a blank space: it restates the scope that was read
/// and offers the one move that widens it.
@available(iOS 16.0, *)
struct PuryEmptyVerdictView: View {
    let language: String
    let scopeLabel: String?
    let onBroaden: (() -> Void)?

    var body: some View {
        PuryAnswerSurface(accent: AdminSurface.secondaryText) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            PuryLocale.text(
                                "Pury_Answer_Empty_Title",
                                language: language,
                                ar: "لا سجلات مطابقة",
                                en: "No matching records"
                            )
                        )
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)

                        Text(
                            scopeLabel.map { scope in
                                PuryLocale.format(
                                    "Pury_Answer_Empty_Scope_Format",
                                    language: language,
                                    ar: "تمت القراءة داخل نطاق: %@",
                                    en: "Read within scope: %@",
                                    scope
                                )
                            } ?? PuryLocale.text(
                                "Pury_Answer_Empty_Body",
                                language: language,
                                ar: "لم يعد أي سجل مصرح لك به لهذا الاستعلام.",
                                en: "No record you are cleared to read matched this query."
                            )
                        )
                        .font(PPBrandFont.regular(size: 12.5, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)

                if let onBroaden {
                    PuryHairline()
                    PuryAnswerAction(
                        title: PuryLocale.text(
                            "Pury_Answer_Broaden",
                            language: language,
                            ar: "وسّع نطاق البحث",
                            en: "Widen the search"
                        ),
                        symbol: "arrow.up.left.and.arrow.down.right",
                        accent: PuryBrand.primary,
                        action: onBroaden
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
